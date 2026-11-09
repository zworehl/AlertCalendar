import Foundation

/// Source-aware checks for fragments that remain grammatical as isolated words.
enum EventTitlePhraseGuard {
    private static let activities = [
        ["working", "session"], ["sprint", "demo"],
        ["stand", "up"], ["check", "in"],
    ]

    static func rejectionReasons(for candidate: String, source: String) -> [String] {
        let sourceTokens = EventTitleEnglishRules.tokens(source)
        let candidateTokens = EventTitleEnglishRules.tokens(candidate)
        let candidateSet = Set(candidateTokens)
        var reasons: [String] = []
        if EventTitleSyntaxValidator.dropsTrailingModifierObject(candidate, source: source) {
            reasons.append("ends inside a source phrase; keep its subject or object")
        }
        let activitySource = sourceTokens.map(activityIdentity)
        let activityCandidate = candidateTokens.map(activityIdentity)
        for phrase in activities where contains(phrase, in: activitySource) {
            // A supported replacement such as Triage need not repeat Working
            // Session, but extracting only half of the activity is incomplete.
            if !Set(activityCandidate).isDisjoint(with: phrase), !contains(phrase, in: activityCandidate) {
                reasons.append("incomplete activity: \(phrase.joined(separator: " "))")
            }
        }

        let identifiers = EventTitlePortableIdentifier.values(in: source)
        if !identifiers.isEmpty {
            let identifierTokens = Set(identifiers.flatMap(EventTitleEnglishRules.tokens))
            let acronymTokens = identifierTokens.union(source.split(whereSeparator: \.isWhitespace)
                .filter { token in
                    let letters = token.filter(\.isLetter)
                    return !letters.isEmpty && letters.allSatisfy(\.isUppercase)
                }
                .flatMap { EventTitleEnglishRules.tokens(String($0)) })
            if !Set(sourceTokens).subtracting(acronymTokens).isEmpty,
               candidateSet.isSubset(of: acronymTokens) {
                reasons.append("retain an activity or subject alongside the identifier")
            }
        }

        if let colon = source.firstIndex(of: ":") {
            let headline = EventTitleEnglishRules.tokens(String(source[..<colon]))
            let subtitle = EventTitleEnglishRules.tokens(String(source[source.index(after: colon)...]))
            if headline.last.map({ ["event", "sale"].contains($0) }) == true {
                if !Set(headline).isSubset(of: candidateSet) {
                    reasons.append("preserve the named event or sale before its promotional subtitle")
                }
                let retainedSubtitle = candidateTokens.filter { !headline.contains($0) }
                if !retainedSubtitle.isEmpty, retainedSubtitle.count < subtitle.count,
                   Set(retainedSubtitle).isSubset(of: Set(subtitle)) {
                    reasons.append("incomplete promotional subtitle; omit it or use a complete phrase")
                }
            }
        }
        return reasons
    }

    private static func activityIdentity(_ token: String) -> String {
        ["work": "working", "demonstration": "demo"][token] ?? token
    }

    private static func contains(_ phrase: [String], in tokens: [String]) -> Bool {
        guard tokens.count >= phrase.count else { return false }
        return (0...(tokens.count - phrase.count)).contains {
            Array(tokens[$0..<$0 + phrase.count]) == phrase
        }
    }
}
