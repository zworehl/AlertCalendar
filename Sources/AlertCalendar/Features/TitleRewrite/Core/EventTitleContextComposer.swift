import Foundation

struct EventTitleContextScaffold: Equatable, Sendable {
    let ownerPhrase: String
    let intent: String
    let qualifierMaximumCharacters: Int
    let originalWordsToAvoid: [String]
}

struct EventTitleIdentifierScaffold: Equatable, Sendable {
    let identifiers: [String]
    let qualifierMaximumCharacters: Int
    let originalWordsToAvoid: [String]
}

enum EventTitleContextComposer {
    static func identifierScaffold(
        for request: EventTitleRewriteRequest
    ) -> EventTitleIdentifierScaffold? {
        let identifiers = EventTitlePortableIdentifier.values(
            in: request.title,
            maximumCount: 2
        )
        guard !identifiers.isEmpty else { return nil }

        let identifierPhrase = identifiers.joined(separator: " ")
        let qualifierMaximumCharacters = request.maximumCharacters
            - identifierPhrase.count
            - 3
        guard qualifierMaximumCharacters >= 3 else { return nil }

        let identifierTokens = Set(identifiers.map(comparableIdentity))
        let originalWordsToAvoid = request.title
            .split { !$0.isLetter && !$0.isNumber && $0 != "#" }
            .map(String.init)
            .filter { !identifierTokens.contains(comparableIdentity($0)) }

        return EventTitleIdentifierScaffold(
            identifiers: identifiers,
            qualifierMaximumCharacters: qualifierMaximumCharacters,
            originalWordsToAvoid: originalWordsToAvoid
        )
    }

    static func scaffold(for request: EventTitleRewriteRequest) -> EventTitleContextScaffold? {
        guard let firstToken = request.title.split(whereSeparator: \.isWhitespace).first else {
            return nil
        }
        let ownerPhrase = String(firstToken)
            .trimmingCharacters(in: .punctuationCharacters.subtracting(
                CharacterSet(charactersIn: "'’")
            ))
        let ownerIdentity = comparableIdentity(ownerPhrase)
        guard ownerIdentity.hasSuffix("'s") || ownerIdentity.hasSuffix("’s") else {
            return nil
        }

        let titleTokens = request.title
            .split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }
            .map(String.init)
        guard let intent = titleTokens.last(where: EventTitleIntentGuard.isCoreIntent) else {
            return nil
        }

        let fixedCharacters = ownerPhrase.count + intent.count + 2
        let qualifierMaximumCharacters = request.maximumCharacters - fixedCharacters
        guard qualifierMaximumCharacters >= 3 else { return nil }

        let excludedIdentities: Set<String> = [
            comparableIdentity(ownerPhrase),
            comparableIdentity(String(ownerPhrase.dropLast(2))),
            comparableIdentity(intent),
        ]
        let originalWordsToAvoid = titleTokens.filter {
            !excludedIdentities.contains(comparableIdentity($0))
        }

        return EventTitleContextScaffold(
            ownerPhrase: ownerPhrase,
            intent: intent,
            qualifierMaximumCharacters: qualifierMaximumCharacters,
            originalWordsToAvoid: originalWordsToAvoid
        )
    }

    static func composedTitle(
        qualifierResponse: String,
        scaffold: EventTitleContextScaffold,
        request: EventTitleRewriteRequest
    ) -> String? {
        var forbiddenIdentities = tokenIdentities(in: request.title)
        forbiddenIdentities.insert(comparableIdentity(scaffold.ownerPhrase))
        for fact in request.distinctiveContextFacts {
            guard let colonIndex = fact.firstIndex(of: ":") else { continue }
            forbiddenIdentities.formUnion(tokenIdentities(in: String(fact[..<colonIndex])))
        }
        let responseTokens = qualifierResponse
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .map {
                $0.trimmingCharacters(
                    in: .punctuationCharacters.union(.symbols)
                )
            }
            .filter { token in
                guard token.count >= 2,
                      token.contains(where: \.isLetter),
                      !token.contains(where: \.isNumber),
                      !forbiddenIdentities.contains(comparableIdentity(token)) else {
                    return false
                }
                let letters = token.filter(\.isLetter)
                return letters.count < 4 || !letters.allSatisfy(\.isUppercase)
            }

        var qualifierWords: [String] = []
        var usedCharacters = 0
        for token in responseTokens.prefix(4) {
            let separatorCharacters = qualifierWords.isEmpty ? 0 : 1
            guard usedCharacters + separatorCharacters + token.count
                    <= scaffold.qualifierMaximumCharacters else {
                continue
            }
            qualifierWords.append(token)
            usedCharacters += separatorCharacters + token.count
        }
        guard !qualifierWords.isEmpty else { return nil }

        let title = [
            scaffold.ownerPhrase,
            qualifierWords.joined(separator: " "),
            scaffold.intent,
        ].joined(separator: " ")
        return AppleIntelligenceEventTitleRewriter.acceptedTitle(title, for: request)
    }

    static func composedIdentifierTitle(
        qualifierResponse: String,
        scaffold: EventTitleIdentifierScaffold,
        request: EventTitleRewriteRequest
    ) -> String? {
        var forbiddenIdentities = Set(scaffold.identifiers.map(comparableIdentity))
        for fact in request.distinctiveContextFacts {
            guard let colonIndex = fact.firstIndex(of: ":") else { continue }
            forbiddenIdentities.formUnion(
                tokenIdentities(in: String(fact[..<colonIndex]))
            )
        }

        let avoidedOriginalWords = Set(scaffold.originalWordsToAvoid.map(comparableIdentity))
        let genericFraming: Set<String> = ["meeting", "connect", "issue", "defect", "event", "reminder", "session"]
        let responseTokens = qualifierResponse
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .map {
                $0.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            }
            .filter { token in
                let identity = comparableIdentity(token)
                guard token.count >= 2,
                      token.contains(where: \.isLetter),
                      !token.contains(where: \.isNumber),
                      !forbiddenIdentities.contains(identity),
                      !genericFraming.contains(identity),
                      !avoidedOriginalWords.contains(identity) else {
                    return false
                }
                let letters = token.filter(\.isLetter)
                return letters.count < 4 || !letters.allSatisfy(\.isUppercase)
            }

        var qualifierWords: [String] = []
        var usedCharacters = 0
        for token in responseTokens.prefix(5) {
            let separatorCharacters = qualifierWords.isEmpty ? 0 : 1
            guard usedCharacters + separatorCharacters + token.count
                    <= scaffold.qualifierMaximumCharacters else {
                continue
            }
            qualifierWords.append(token)
            usedCharacters += separatorCharacters + token.count
        }
        guard !qualifierWords.isEmpty else { return nil }

        let title = "\(qualifierWords.joined(separator: " ")) · \(scaffold.identifiers.joined(separator: " "))"
        return AppleIntelligenceEventTitleRewriter.acceptedTitle(title, for: request)
    }

    private static func tokenIdentities(in value: String) -> Set<String> {
        Set(
            value
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .map(comparableIdentity)
        )
    }

    private static func comparableIdentity(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
    }
}
