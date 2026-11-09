import Foundation

/// Hard constraints shared by model drafts and local fallback candidates.
/// An impossible budget falls back to the original title for visual truncation.
enum EventTitleMeaningGuard {
    static func missingTerms(in candidate: String, source: String) -> [String] {
        if let birthday = EventBirthdayTitle.parse(source) {
            let identity = EventTitleEnglishRules.tokens(candidate)
            return birthday.variants.contains { EventTitleEnglishRules.tokens($0) == identity }
                ? [] : ["birthday and person"]
        }
        if let anniversary = EventAnniversaryTitle.parse(source) {
            let identity = EventTitleEnglishRules.tokens(candidate).filter { $0 != "and" }
            return anniversary.variants.contains { EventTitleEnglishRules.tokens($0) == identity }
                ? [] : ["anniversary kind and people"]
        }

        let sourceTokens = EventTitleEnglishRules.tokens(source)
        let candidateTokens = EventTitleEnglishRules.tokens(candidate)
        let candidateSet = Set(candidateTokens)
        var required = sourceTokens.filter {
            EventTitleIntentGuard.isCoreIntent($0) || EventTitleSemanticSignals.isMeaningChanging($0)
        }
        // These activities are only generic framing when a more specific
        // activity is already present (e.g. "meeting to review the budget").
        let activities: Set<String> = ["review", "plan", "planning", "call", "training"]
        required += sourceTokens.filter { activities.contains($0) }
        if required.isEmpty, sourceTokens.contains("meeting") { required.append("meeting") }
        required += associatedNames(in: source)
        // A weekday in the subject may differ from the event's scheduled day.
        for weekday in ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"] {
            if source.range(of: "(?i)\\b" + weekday + "['’]s\\b", options: .regularExpression) != nil {
                required.append(weekday)
            }
        }

        // Keep numbers in their full form, including version and flight IDs.
        // Birthday ages are handled above; other numbers are not assumed optional.
        let numberedTokens = source.split(whereSeparator: \.isWhitespace).map(String.init)
            .map { $0.trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "#@"))) }
            .filter { $0.contains(where: \.isNumber) }
        var missing = required.filter {
            !EventTitleSemanticSignals.preserves(sourceTerm: $0, candidateIdentities: candidateSet)
        }
        let candidateNumbered = Set(candidate.split(whereSeparator: \.isWhitespace).map {
            EventTitleEnglishRules.identity(String($0).trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "#@"))))
        })
        missing += numberedTokens.filter { !candidateNumbered.contains(EventTitleEnglishRules.identity($0)) }

        // Never manufacture a status or change its tense while shortening.
        let sourceGroups = Set(sourceTokens.compactMap(EventTitleSemanticSignals.group))
        missing += candidateTokens.filter {
            guard let group = EventTitleSemanticSignals.group(for: $0) else { return false }
            return !sourceGroups.contains(group)
        }.map { "unsupported state: \($0)" }

        // Preserve the object of negation and directional/temporal relations.
        let connectors: Set<String> = ["not", "no", "never", "without", "before", "after", "pick", "drop", "follow"]
        for index in sourceTokens.indices where connectors.contains(sourceTokens[index]) && index + 1 < sourceTokens.count {
            let pair = Array(sourceTokens[index...index + 1])
            if !contains(pair, in: candidateTokens) { missing.append(pair.joined(separator: " ")) }
        }
        if sourceTokens.contains("christmas") || sourceTokens.contains("year") {
            if sourceTokens.contains("day"), !candidateSet.contains("day") { missing.append("day") }
        }
        // Route endpoints and their order must survive, including Unicode dashes.
        if sourceTokens.contains("flight") {
            let airports = source.split { !$0.isLetter }.map(String.init).filter {
                $0.count == 3 && $0.allSatisfy(\.isUppercase)
            }.map(EventTitleEnglishRules.identity)
            let candidateAirports = candidateTokens.filter { airports.contains($0) }
            if airports != candidateAirports { missing.append("flight route") }
        }
        return missing
    }

    private static func associatedNames(in source: String) -> [String] {
        // English possessives identify owners anywhere in the title. Activity
        // recipients are protected without making every meeting attendee required.
        let patterns = [
            #"\b([\p{L}][\p{L}’-]*)['’]s\b"#,
            #"(?i:pick up|drop off|call|plan|planning)\s+([\p{Lu}][\p{L}’-]*)"#,
            #"(?i:gift for|send to|deliver to)\s+([\p{Lu}][\p{L}’-]*)"#,
        ]
        return patterns.flatMap { pattern -> [String] in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            return regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap {
                guard let range = Range($0.range(at: 1), in: source) else { return nil }
                return EventTitleEnglishRules.canonical(String(source[range]))
            }
        }
    }

    private static func contains(_ phrase: [String], in tokens: [String]) -> Bool {
        guard tokens.count >= phrase.count else { return false }
        return (0...(tokens.count - phrase.count)).contains { start in
            Array(tokens[start..<start + phrase.count]) == phrase
        }
    }
}
