import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

protocol EventTitleRewriting: Sendable {
    var availability: AgendaSummaryAvailability { get }
    func rewriteTitle(for request: EventTitleRewriteRequest) async throws -> String
}

final class AppleIntelligenceEventTitleRewriter: EventTitleRewriting, @unchecked Sendable {
    struct Draft: Equatable, Sendable {
        let title: String
    }

    typealias AvailabilityProvider = @Sendable () -> AgendaSummaryAvailability
    typealias Responder = @Sendable (_ instructions: String, _ prompt: String) async throws -> Draft

    private let availabilityProvider: AvailabilityProvider
    private let responder: Responder

    init() {
        availabilityProvider = { AppleIntelligenceAgendaSummaryClient.systemAvailability }
        responder = { instructions, prompt in
            try await Self.respondWithSystemModel(instructions: instructions, prompt: prompt)
        }
    }

    init(
        availabilityProvider: @escaping AvailabilityProvider,
        responder: @escaping Responder
    ) {
        self.availabilityProvider = availabilityProvider
        self.responder = responder
    }

    var availability: AgendaSummaryAvailability {
        availabilityProvider()
    }

    func rewriteTitle(for request: EventTitleRewriteRequest) async throws -> String {
        let maximumCharacters = request.maximumCharacters
        guard availability.isAvailable else { throw EventTitleRewriteError.unavailable }
        guard AppSettingsRules.allowsAppleIntelligenceTitleRewrite(maximumCharacters: maximumCharacters) else {
            throw EventTitleRewriteError.characterLimitTooSmall
        }

        let instructions = Self.instructions(maximumCharacters: maximumCharacters)
        let result = try await responder(
            instructions,
            Self.prompt(request: request)
        )
        try Task.checkCancellation()
        if let accepted = Self.acceptedTitle(result.title, for: request) {
            return try await contextRefinedTitleIfUseful(
                accepted,
                request: request,
                instructions: instructions
            )
        }

        let retry = try await responder(
            instructions,
            Self.retryPrompt(
                request: request,
                rejectedDraft: result.title
            )
        )
        try Task.checkCancellation()
        if let accepted = Self.acceptedTitle(retry.title, for: request) {
            return try await contextRefinedTitleIfUseful(
                accepted,
                request: request,
                instructions: instructions
            )
        }
        do {
            if let composedTitle = try await composedContextualTitleIfAvailable(
                request: request
            ) {
                return composedTitle
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return deterministicFallbackTitle(for: request)
        }
        return deterministicFallbackTitle(for: request)
    }

    private func deterministicFallbackTitle(for request: EventTitleRewriteRequest) -> String {
        EventTitleSemanticCompactor.compact(
            title: request.title,
            maximumCharacters: request.maximumCharacters,
            supportingText: [
                request.description,
                request.location,
                request.calendarName,
            ].compactMap { $0 } + request.distinctiveContextFacts
        )
    }

    private func contextRefinedTitleIfUseful(
        _ acceptedTitle: String,
        request: EventTitleRewriteRequest,
        instructions: String
    ) async throws -> String {
        let currentCoverage = Self.distinctiveContextCoverageScore(
            acceptedTitle,
            request: request
        )
        guard currentCoverage == 0,
              !request.distinctiveContextFacts.isEmpty else {
            return acceptedTitle
        }

        do {
            if let composedTitle = try await composedContextualTitleIfAvailable(
                request: request
            ) {
                return composedTitle
            }

            let refinement = try await responder(
                instructions,
                Self.contextRefinementPrompt(
                    request: request,
                    currentDraft: acceptedTitle
                )
            )
            try Task.checkCancellation()
            guard let acceptedRefinement = Self.acceptedTitle(
                refinement.title,
                for: request
            ), Self.distinctiveContextCoverageScore(
                acceptedRefinement,
                request: request
            ) > currentCoverage else {
                return acceptedTitle
            }
            return acceptedRefinement
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return acceptedTitle
        }
    }

    private func composedContextualTitleIfAvailable(
        request: EventTitleRewriteRequest
    ) async throws -> String? {
        guard !request.distinctiveContextFacts.isEmpty else {
            return nil
        }

        if let identifierScaffold = EventTitleContextComposer.identifierScaffold(
            for: request
        ) {
            let qualifier = try await responder(
                Self.contextQualifierInstructions(),
                Self.identifierQualifierPrompt(
                    request: request,
                    scaffold: identifierScaffold
                )
            )
            try Task.checkCancellation()
            if let composed = EventTitleContextComposer.composedIdentifierTitle(
                qualifierResponse: qualifier.title,
                scaffold: identifierScaffold,
                request: request
            ) {
                return composed
            }
        }

        guard let scaffold = EventTitleContextComposer.scaffold(for: request) else {
            return nil
        }
        let qualifier = try await responder(
            Self.contextQualifierInstructions(),
            Self.contextQualifierPrompt(
                request: request,
                scaffold: scaffold
            )
        )
        try Task.checkCancellation()
        if Self.qualifierCopiesAttachmentWording(qualifier.title, request: request) {
            let correctedQualifier = try await responder(
                Self.contextQualifierInstructions(),
                Self.contextQualifierCorrectionPrompt(
                    request: request,
                    scaffold: scaffold,
                    rejectedQualifier: qualifier.title
                )
            )
            try Task.checkCancellation()
            if let correctedTitle = EventTitleContextComposer.composedTitle(
                qualifierResponse: correctedQualifier.title,
                scaffold: scaffold,
                request: request
            ) {
                return correctedTitle
            }
        }
        return EventTitleContextComposer.composedTitle(
            qualifierResponse: qualifier.title,
            scaffold: scaffold,
            request: request
        )
    }

    static func prompt(request: EventTitleRewriteRequest) -> String {
        """
        Rewrite this calendar title so it fits within \(request.maximumCharacters) characters. First identify the original core intent, then identify the most title-worthy specific facts supported by the complete processed context, and finally compose the clearest faithful title that fits. Preserve the core intent while replacing generic wording with stronger supported specificity when useful:
        \(jsonString(for: promptPayload(request: request)))
        """
    }

    static func retryPrompt(
        request: EventTitleRewriteRequest,
        rejectedDraft: String
    ) -> String {
        var payload = promptPayload(request: request)
        payload["rejectedDraft"] = rejectedDraft
        payload["rejectionReasons"] = rejectionReasons(
            for: rejectedDraft,
            request: request
        )
        return """
        The previous draft was not faithful or did not satisfy the format. Rewrite the original title again using at most \(request.maximumCharacters) characters and correct every rejection reason. Return only the title field.
        \(jsonString(for: payload))
        """
    }

    static func acceptedTitle(_ value: String, for request: EventTitleRewriteRequest) -> String? {
        guard let accepted = acceptedTitle(
            value,
            maximumCharacters: request.maximumCharacters
        ) else {
            return nil
        }
        let missingTerms = protectedTermsMissing(from: accepted, request: request)
            + EventTitleMeaningGuard.missingTerms(in: accepted, source: request.title)
        guard missingTerms.isEmpty,
              EventTitlePhraseGuard.rejectionReasons(for: accepted, source: request.title).isEmpty,
              EventBirthdayTitle.parse(request.title) != nil
                || EventAnniversaryTitle.parse(request.title) != nil
                || EventTitleEnglishRules.supportsRewrite(accepted, source: request.title),
              !containsNovelAttachmentFieldLabel(accepted, request: request),
              hasSemanticEvidence(accepted, request: request) else {
            return nil
        }
        return accepted
    }

    static func acceptedTitle(_ value: String, maximumCharacters: Int) -> String? {
        let normalizedValue = normalized(value)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’"))
        guard !normalizedValue.isEmpty,
              normalizedValue.count <= maximumCharacters,
              !normalizedValue.contains("…"),
              !normalizedValue.hasSuffix("..."),
              !EventTitleSyntaxValidator.hasIncompleteTrailingPhrase(normalizedValue) else {
            return nil
        }
        return normalizedValue
    }

    private static func promptPayload(request: EventTitleRewriteRequest) -> [String: Any] {
        var payload: [String: Any] = [
            "title": request.title,
            "urlHosts": request.urlHosts,
            "hasMeetingURL": request.hasMeetingURL,
            "attachmentNames": request.attachmentNames,
            "attachmentPreviews": request.attachmentPreviews,
            "distinctiveAttachmentFacts": request.distinctiveAttachmentFacts,
            "mailContexts": request.mailContexts,
            "distinctiveMailFacts": request.distinctiveMailFacts,
        ]
        if let description = request.description {
            payload["description"] = description
        }
        if let itemKind = request.itemKind {
            payload["itemKind"] = itemKind
        }
        if let startsAt = request.startsAt {
            payload["startsAt"] = dateString(
                startsAt,
                timeZoneIdentifier: request.timeZoneIdentifier
            )
        }
        if let endsAt = request.endsAt {
            payload["endsAt"] = dateString(
                endsAt,
                timeZoneIdentifier: request.timeZoneIdentifier
            )
        }
        if let timeZoneIdentifier = request.timeZoneIdentifier {
            payload["timeZone"] = timeZoneIdentifier
        }
        if let isAllDay = request.isAllDay {
            payload["allDay"] = isAllDay
        }
        if let location = request.location {
            payload["location"] = location
        }
        if let calendarName = request.calendarName {
            payload["calendar"] = calendarName
        }
        if let isRecurring = request.isRecurring {
            payload["recurring"] = isRecurring
        }
        if let organizerName = request.organizerName {
            payload["organizer"] = organizerName
        }
        if !request.attendeeNames.isEmpty {
            payload["attendees"] = request.attendeeNames
        }
        return payload
    }

    private static func dateString(
        _ date: Date,
        timeZoneIdentifier: String?
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        formatter.timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? .autoupdatingCurrent
        return formatter.string(from: date)
    }

    private static func rejectionReasons(
        for value: String,
        request: EventTitleRewriteRequest
    ) -> [String] {
        var reasons: [String] = []
        let normalizedValue = normalized(value)
        if normalizedValue.isEmpty {
            reasons.append("empty title")
        }
        if normalizedValue.count > request.maximumCharacters {
            reasons.append("exceeds the character limit")
        }
        if normalizedValue.contains("…") || normalizedValue.hasSuffix("...") {
            reasons.append("contains an ellipsis")
        }
        if EventTitleSyntaxValidator.hasIncompleteTrailingPhrase(normalizedValue) {
            reasons.append("ends with an incomplete trailing function word")
        }
        reasons += EventTitlePhraseGuard.rejectionReasons(for: normalizedValue, source: request.title)
        let missingTerms = protectedTermsMissing(from: normalizedValue, request: request)
            + EventTitleMeaningGuard.missingTerms(in: normalizedValue, source: request.title)
        if !missingTerms.isEmpty {
            reasons.append("missing required terms: \(missingTerms.joined(separator: ", "))")
        }
        return reasons.isEmpty ? ["invalid title format"] : reasons
    }

    private static func protectedTermsMissing(
        from candidate: String,
        request: EventTitleRewriteRequest
    ) -> [String] {
        if EventBirthdayTitle.parse(request.title) != nil || EventAnniversaryTitle.parse(request.title) != nil {
            return EventTitleMeaningGuard.missingTerms(in: candidate, source: request.title)
        }
        let candidateTokenIdentities = comparableTokenIdentities(in: candidate)
        return protectedTerms(
            in: request.title,
            maximumCharacters: request.maximumCharacters
        )
        .filter { term in
            !EventTitleSemanticSignals.preserves(
                sourceTerm: term,
                candidateIdentities: candidateTokenIdentities
            )
        }
    }

    private static func protectedTerms(
        in title: String,
        maximumCharacters: Int
    ) -> [String] {
        let tokens = title.split { character in
            !character.isLetter && !character.isNumber && character != "#" && character != "@"
        }
        let letters = title.filter(\.isLetter)
        let uppercaseLetters = letters.filter(\.isUppercase)
        let titleIsMostlyUppercase = !letters.isEmpty
            && uppercaseLetters.count * 5 >= letters.count * 4

        var requiredTerms: [String] = []
        var supplementalTerms: [String] = []
        var identities: Set<String> = []
        func appendUnique(_ term: String, to terms: inout [String]) {
            let identity = comparableIdentity(for: term)
            guard identities.insert(identity).inserted else { return }
            terms.append(term)
        }
        if let possessiveOwner = possessiveOwnerTerm(in: title) {
            appendUnique(possessiveOwner, to: &requiredTerms)
        }
        for tokenSlice in tokens {
            let token = String(tokenSlice)
            let tokenLetters = token.filter(\.isLetter)
            let containsNumber = token.contains(where: \.isNumber)
            let isTaggedIdentifier = token.first == "#" || token.first == "@"
            let isMeaningChanging = EventTitleSemanticSignals.isMeaningChanging(token)
            let isAcronym = !titleIsMostlyUppercase
                && tokenLetters.count >= 2
                && tokenLetters.count <= 12
                && tokenLetters.allSatisfy(\.isUppercase)
            let isCoreIntent = EventTitleIntentGuard.isCoreIntent(token)
            guard containsNumber || isTaggedIdentifier || isAcronym || isCoreIntent
                    || isMeaningChanging else {
                continue
            }

            let comparableToken = token.trimmingCharacters(
                in: CharacterSet(charactersIn: "#@")
            )
            guard !comparableToken.isEmpty else { continue }
            if isMeaningChanging || isCoreIntent {
                appendUnique(comparableToken, to: &requiredTerms)
            } else {
                appendUnique(comparableToken, to: &supplementalTerms)
            }
        }

        let terms = requiredTerms + supplementalTerms
        let combinedLength = terms.reduce(0) { $0 + $1.count } + max(0, terms.count - 1)
        let safeIdentifierBudget = max(1, Int(Double(maximumCharacters) * 0.65))
        if combinedLength <= safeIdentifierBudget {
            return terms
        }
        return requiredTerms
    }

    private static func possessiveOwnerTerm(in title: String) -> String? {
        guard let firstToken = title.split(whereSeparator: \.isWhitespace).first else {
            return nil
        }
        let rawToken = String(firstToken)
            .trimmingCharacters(in: .punctuationCharacters.subtracting(
                CharacterSet(charactersIn: "'’")
            ))
        let lowercasedToken = rawToken.lowercased()
        let suffix: String
        if lowercasedToken.hasSuffix("'s") {
            suffix = "'s"
        } else if lowercasedToken.hasSuffix("’s") {
            suffix = "’s"
        } else {
            return nil
        }
        let owner = String(rawToken.dropLast(suffix.count))
        return owner.count >= 2 ? owner : nil
    }

    private static func comparableTokenIdentities(in value: String) -> Set<String> {
        Set(
            value
                .split { !$0.isLetter && !$0.isNumber && $0 != "#" && $0 != "@" }
                .map(String.init)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#@")) }
                .filter { !$0.isEmpty }
                .map(comparableIdentity)
        )
    }

    static func comparableIdentity(for value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
    }

    private static func respondWithSystemModel(
        instructions: String,
        prompt: String
    ) async throws -> Draft {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                throw EventTitleRewriteError.unavailable
            }
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(
                to: prompt,
                generating: AppleEventTitleOutput.self,
                options: GenerationOptions(sampling: .greedy)
            )
            return Draft(title: response.content.title)
        }
        #endif
        throw EventTitleRewriteError.unavailable
    }
}
