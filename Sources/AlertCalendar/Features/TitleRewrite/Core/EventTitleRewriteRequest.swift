import Foundation

struct EventTitleRewriteRequest: Equatable, Hashable, Sendable {
    private static let maximumDescriptionCharacters = 1_600
    private static let maximumURLHostCharacters = 100
    private static let maximumURLHosts = 8
    private static let maximumAttachmentNameCharacters = 120
    private static let maximumAttachmentNames = 20
    private static let maximumAttachmentContexts = 6
    private static let maximumAttachmentContextCharacters = 2_400
    private static let maximumAttachmentContextCharactersTotal = 7_200
    private static let maximumMailContexts = 6
    private static let maximumMailContextCharacters = 1_200
    private static let maximumMailContextCharactersTotal = 3_600
    private static let maximumDistinctiveAttachmentFacts = 12
    private static let maximumDistinctiveAttachmentFactCharacters = 180
    private static let maximumParticipantNameCharacters = 80
    private static let maximumParticipantNames = 12

    let title: String
    let description: String?
    let urlHosts: [String]
    let hasMeetingURL: Bool
    let attachmentNames: [String]
    let attachmentPreviews: [String]
    let distinctiveAttachmentFacts: [String]
    let mailContexts: [String]
    let distinctiveMailFacts: [String]
    let itemKind: String?
    let startsAt: Date?
    let endsAt: Date?
    let timeZoneIdentifier: String?
    let isAllDay: Bool?
    let location: String?
    let calendarName: String?
    let isRecurring: Bool?
    let organizerName: String?
    let attendeeNames: [String]
    let maximumCharacters: Int

    var distinctiveContextFacts: [String] {
        var seen: Set<String> = []
        return (distinctiveDescriptionFacts + distinctiveAttachmentFacts + distinctiveMailFacts).filter { fact in
            seen.insert(Self.comparableIdentity(fact)).inserted
        }
    }

    var distinctiveDescriptionFacts: [String] {
        let boilerplate = [
            "join with", "join the meeting", "or dial", "more phone numbers",
            "learn more about", "please do not edit", "meeting id", "passcode",
        ]
        let prose = (description ?? "").components(separatedBy: .newlines)
            .filter { line in
                let identity = Self.comparableIdentity(line)
                return !boilerplate.contains(where: identity.hasPrefix)
            }
            .joined(separator: "\n")
        let selected = RelevantContextSelector.selectedText(
            from: prose, referenceText: [title], maximumCharacters: 1_200, maximumSegments: 4
        )
        return (selected ?? "").components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map { "Event context: \(String($0.prefix(360)))" }
    }

    init(
        title: String,
        description: String? = nil,
        urlHosts: [String] = [],
        hasMeetingURL: Bool = false,
        attachmentNames: [String] = [],
        attachmentPreviews: [String] = [],
        mailContexts: [String] = [],
        itemKind: String? = nil,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        timeZoneIdentifier: String? = nil,
        isAllDay: Bool? = nil,
        location: String? = nil,
        calendarName: String? = nil,
        isRecurring: Bool? = nil,
        organizerName: String? = nil,
        attendeeNames: [String] = [],
        maximumCharacters: Int
    ) {
        let normalizedTitle = AppleIntelligenceEventTitleRewriter.normalized(title)
        let boundedLocation = Self.boundedMetadata(location, maximumCharacters: 180)
        let boundedCalendarName = Self.boundedMetadata(calendarName, maximumCharacters: 80)

        self.title = normalizedTitle
        self.location = boundedLocation
        self.calendarName = boundedCalendarName
        self.description = RelevantContextSelector.selectedText(
            from: description,
            referenceText: [normalizedTitle, boundedLocation, boundedCalendarName]
                .compactMap { $0 },
            maximumCharacters: Self.maximumDescriptionCharacters,
            maximumSegments: 14
        )
        self.urlHosts = Self.boundedURLHosts(urlHosts)
        self.hasMeetingURL = hasMeetingURL
        self.attachmentNames = Self.boundedAttachmentNames(attachmentNames)
        let boundedAttachmentPreviews = Self.boundedAttachmentContexts(
            attachmentPreviews,
            referenceText: [
                normalizedTitle,
                self.description,
                boundedLocation,
                boundedCalendarName,
            ].compactMap { $0 } + self.attachmentNames
        )
        self.attachmentPreviews = boundedAttachmentPreviews
        self.distinctiveAttachmentFacts = Self.distinctiveAttachmentFacts(
            in: boundedAttachmentPreviews,
            referenceText: [
                normalizedTitle,
                self.description,
                boundedLocation,
                boundedCalendarName,
            ].compactMap { $0 } + self.attachmentNames
        )
        let boundedMailContexts = Self.boundedContexts(
            mailContexts,
            referenceText: [
                normalizedTitle,
                self.description,
                boundedLocation,
                boundedCalendarName,
            ].compactMap { $0 } + self.attachmentNames,
            maximumContexts: Self.maximumMailContexts,
            maximumCharactersPerContext: Self.maximumMailContextCharacters,
            maximumTotalCharacters: Self.maximumMailContextCharactersTotal
        )
        self.mailContexts = boundedMailContexts
        self.distinctiveMailFacts = Self.distinctiveAttachmentFacts(
            in: boundedMailContexts,
            referenceText: [
                normalizedTitle,
                self.description,
                boundedLocation,
                boundedCalendarName,
            ].compactMap { $0 } + self.attachmentNames
        )
        let normalizedItemKind = AlertCalendarString.trimmedNonEmpty(itemKind)?.lowercased()
        self.itemKind = ["event", "reminder"].contains(normalizedItemKind) ? normalizedItemKind : nil
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.timeZoneIdentifier = Self.boundedMetadata(
            timeZoneIdentifier,
            maximumCharacters: 80
        )
        self.isAllDay = isAllDay
        self.isRecurring = isRecurring
        self.organizerName = Self.boundedParticipantName(organizerName)
        self.attendeeNames = Self.boundedParticipantNames(attendeeNames)
        self.maximumCharacters = AppSettingsRules.normalizedEventTitleMaxCharacters(maximumCharacters)
    }

    private static func boundedURLHosts(_ values: [String]) -> [String] {
        Array(
            Set(
                values
                    .compactMap { AlertCalendarString.trimmedNonEmpty($0) }
                    .map { $0.lowercased() }
                    .map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
                    .map { String($0.prefix(maximumURLHostCharacters)) }
            )
        )
        .sorted()
        .prefix(maximumURLHosts)
        .map { $0 }
    }

    private static func boundedAttachmentNames(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { rawValue -> String? in
            guard let value = AlertCalendarString.trimmedNonEmpty(rawValue) else { return nil }
            let fileName = (value as NSString).lastPathComponent
            let boundedName = String(fileName.prefix(maximumAttachmentNameCharacters))
            let identity = comparableIdentity(boundedName)
            return seen.insert(identity).inserted ? boundedName : nil
        }
        .prefix(maximumAttachmentNames)
        .map { $0 }
    }

    private static func boundedAttachmentContexts(
        _ values: [String],
        referenceText: [String]
    ) -> [String] {
        boundedContexts(
            values,
            referenceText: referenceText,
            maximumContexts: maximumAttachmentContexts,
            maximumCharactersPerContext: maximumAttachmentContextCharacters,
            maximumTotalCharacters: maximumAttachmentContextCharactersTotal
        )
    }

    private static func boundedContexts(
        _ values: [String],
        referenceText: [String],
        maximumContexts: Int,
        maximumCharactersPerContext: Int,
        maximumTotalCharacters: Int
    ) -> [String] {
        var contexts: [String] = []
        var usedCharacters = 0

        for value in values.prefix(maximumContexts) {
            let separatorCharacters = contexts.isEmpty ? 0 : 1
            let remainingCharacters = maximumTotalCharacters
                - usedCharacters
                - separatorCharacters
            guard remainingCharacters >= 240 else { break }
            guard let context = RelevantContextSelector.selectedText(
                from: value,
                referenceText: referenceText,
                maximumCharacters: min(maximumCharactersPerContext, remainingCharacters),
                maximumSegments: 24
            ) else {
                continue
            }
            contexts.append(context)
            usedCharacters += separatorCharacters + context.count
        }

        return contexts
    }

    private static func distinctiveAttachmentFacts(
        in contexts: [String],
        referenceText: [String]
    ) -> [String] {
        struct Candidate {
            let contextIndex: Int
            let index: Int
            let fact: String
            let score: Int
        }

        let referenceTokens = tokenIdentities(in: referenceText.joined(separator: " "))
        var candidates: [Candidate] = []
        var seen: Set<String> = []
        var index = 0

        for (contextIndex, context) in contexts.enumerated() {
            for rawLine in context.components(separatedBy: .newlines) {
                let line = AppleIntelligenceEventTitleRewriter.normalized(rawLine)
                for (label, value) in structuredFacts(in: line) {
                    defer { index += 1 }
                    let informativeValue = ["[link]", "[email]", "[number]", "[account]", "[path]"]
                        .reduce(value) { partialResult, placeholder in
                            partialResult.replacingOccurrences(of: placeholder, with: "")
                        }
                    guard value.count >= 3,
                          informativeValue.contains(where: \.isLetter) else {
                        continue
                    }

                    let boundedFact = String(
                        "\(label): \(value)".prefix(maximumDistinctiveAttachmentFactCharacters)
                    )
                    let identity = comparableIdentity(boundedFact)
                    guard seen.insert(identity).inserted else { continue }

                    let valueTokens = tokenIdentities(in: value)
                    let novelTokenCount = valueTokens.subtracting(referenceTokens).count
                    let score = RelevantContextSelector.relevanceScore(
                        for: boundedFact,
                        referenceText: referenceText
                    ) + min(6, novelTokenCount) * 12
                    candidates.append(
                        Candidate(
                            contextIndex: contextIndex,
                            index: index,
                            fact: boundedFact,
                            score: score
                        )
                    )
                }
            }
        }

        let rankedCandidates = candidates.sorted { left, right in
            if left.score != right.score {
                return left.score > right.score
            }
            return left.index < right.index
        }
        let factsPerContext = max(
            1,
            maximumDistinctiveAttachmentFacts / max(1, contexts.count)
        )
        var selectedIndexes: Set<Int> = []
        for contextIndex in contexts.indices {
            for candidate in rankedCandidates
                .filter({ $0.contextIndex == contextIndex })
                .prefix(factsPerContext) {
                selectedIndexes.insert(candidate.index)
            }
        }
        for candidate in rankedCandidates where selectedIndexes.count < maximumDistinctiveAttachmentFacts {
            selectedIndexes.insert(candidate.index)
        }

        return candidates
            .filter { selectedIndexes.contains($0.index) }
            .sorted { left, right in
                if left.score != right.score {
                    return left.score > right.score
                }
                return left.index < right.index
            }
            .prefix(maximumDistinctiveAttachmentFacts)
            .map(\.fact)
    }

    private static func structuredFacts(in line: String) -> [(String, String)] {
        let pattern = #"(?<![\p{L}\p{N}])([\p{L}][\p{L}\p{N} ]{1,59}):\s*"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsLine = line as NSString
        let matches = expression.matches(
            in: line,
            range: NSRange(location: 0, length: nsLine.length)
        )
        return matches.enumerated().compactMap { offset, match in
            guard match.numberOfRanges >= 2 else { return nil }
            let valueStart = NSMaxRange(match.range)
            let valueEnd = offset + 1 < matches.count
                ? matches[offset + 1].range.location
                : nsLine.length
            guard valueEnd > valueStart else { return nil }
            let label = nsLine.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespaces)
            let value = nsLine.substring(
                with: NSRange(location: valueStart, length: valueEnd - valueStart)
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            guard label.count >= 2, label.count <= 60, !value.isEmpty else { return nil }
            return (label, value)
        }
    }

    private static func tokenIdentities(in value: String) -> Set<String> {
        Set(
            value
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count >= 3 }
                .map(comparableIdentity)
        )
    }

    private static func boundedMetadata(
        _ value: String?,
        maximumCharacters: Int
    ) -> String? {
        guard let value = AlertCalendarString.trimmedNonEmpty(value) else { return nil }
        let normalized = AppleIntelligenceEventTitleRewriter.normalized(
            RelevantContextSelector.redacted(value)
        )
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(maximumCharacters))
    }

    private static func boundedParticipantName(_ value: String?) -> String? {
        guard let name = boundedMetadata(
            value,
            maximumCharacters: maximumParticipantNameCharacters
        ), name != "[email]" else {
            return nil
        }
        return name
    }

    private static func boundedParticipantNames(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            guard let name = boundedParticipantName(value) else { return nil }
            return seen.insert(comparableIdentity(name)).inserted ? name : nil
        }
        .prefix(maximumParticipantNames)
        .map { $0 }
    }

    private static func comparableIdentity(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
    }
}
