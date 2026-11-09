import Foundation
import NaturalLanguage

/// Produces a useful, complete title when the model is unavailable or returns
/// a response that cannot be accepted. This is deliberately extractive: it
/// preserves source order and uses only approved English abbreviations.
enum EventTitleSemanticCompactor {
    private struct Token {
        let text: String
        let identity: String
        let lexicalTag: NLTag?
        let index: Int
    }

    private struct Candidate {
        let text: String
        let indices: [Int]
        let score: Int
    }

    private static let genericTerms: Set<String> = [
        "activity", "appointment", "calendar", "call", "catchup", "chat",
        "connect", "connection", "discussion", "event", "gathering", "invite",
        "invitation", "meeting", "reminder", "review", "session", "sync",
        "task", "activity", "plan", "planning", "schedule", "scheduled",
        "annual", "conference", "festival", "monthly",
        "series", "summit", "tournament", "weekly", "world", "worldwide",
    ]

    private static let functionTags: Set<NLTag> = [
        .conjunction,
        .determiner,
        .particle,
        .preposition,
        .pronoun,
    ]

    private static let functionWords: Set<String> = [
        "a", "an", "and", "at", "by", "for", "from", "in", "of", "on", "or", "the", "to", "with",
    ]

    private static let stronglyGenericTerms: Set<String> = [
        "world", "worldwide", "championship", "conference", "festival", "summit",
        "tournament", "series",
    ]

    static func compact(
        title rawTitle: String,
        maximumCharacters: Int,
        supportingText: [String] = []
    ) -> String {
        let maximumCharacters = AppSettingsRules.normalizedEventTitleMaxCharacters(
            maximumCharacters
        )
        let title = normalizedTitle(rawTitle)
        guard !title.isEmpty else { return title }
        if title.count <= maximumCharacters,
           isComplete(title) {
            return title
        }

        if let birthday = EventBirthdayTitle.parse(title) {
            return birthday.compact(maximumCharacters: maximumCharacters) ?? title
        }
        if let anniversary = EventAnniversaryTitle.parse(title) {
            return anniversary.compact(maximumCharacters: maximumCharacters) ?? title
        }
        guard EventTitleEnglishRules.supportsProse(title) else { return title }
        let tokens = tokenize(title)
        guard !tokens.isEmpty else {
            return hardFallback(title, maximumCharacters: maximumCharacters)
        }

        let contextTokens = Set(
            supportingText
                .joined(separator: " ")
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .map(comparableIdentity)
        )
        let protectedIndexes = Set(
            tokens.indices.filter { isProtected(tokens[$0], in: tokens) }
        )

        var candidates: [Candidate] = []
        var seen: Set<String> = []
        func addCandidate(indices rawIndices: [Int]) {
            let indices = rawIndices.sorted()
            guard !indices.isEmpty,
                  indices.allSatisfy(tokens.indices.contains),
                  indices == Array(Set(indices)).sorted() else {
                return
            }
            let original = indices.map { tokens[$0].text }.joined(separator: " ")
            for (abbreviationPenalty, text) in [original, EventTitleEnglishRules.abbreviated(original)].enumerated() {
                guard text.count <= maximumCharacters,
                      isComplete(text),
                      AppleIntelligenceEventTitleRewriter.acceptedTitle(
                        text, for: EventTitleRewriteRequest(title: title, maximumCharacters: maximumCharacters)
                      ) != nil,
                      seen.insert(comparableIdentity(text)).inserted else { continue }
                candidates.append(Candidate(
                    text: text,
                    indices: indices,
                    score: score(
                        indices: indices, tokens: tokens, protectedIndexes: protectedIndexes,
                        contextTokens: contextTokens, maximumCharacters: maximumCharacters
                    ) - abbreviationPenalty * 3
                ))
            }
        }

        // Every contiguous phrase is a safe, natural candidate. This handles
        // subjects in the middle of titles such as “Meeting to discuss Project X”.
        for start in tokens.indices {
            for end in start ..< tokens.count {
                addCandidate(indices: Array(start ... end))
            }
        }

        // Also consider a concise lead plus a meaningful tail. This is the
        // important case for titles with a brand/project followed by a stage,
        // status, or date-like qualifier, e.g. “GeoGuessr Finals Day”.
        let maximumLeadTokens = min(tokens.count, 6)
        let maximumTailTokens = min(tokens.count, 6)
        for leadEnd in 0 ..< maximumLeadTokens {
            for tailStart in (leadEnd + 1) ..< tokens.count {
                guard tokens.count - tailStart <= maximumTailTokens else { continue }
                addCandidate(
                    indices: Array(0 ... leadEnd) + Array(tailStart ..< tokens.count)
                )
            }
        }

        guard let best = candidates.max(by: { left, right in
            if left.score != right.score {
                return left.score < right.score
            }
            if left.indices.count != right.indices.count {
                return left.indices.count < right.indices.count
            }
            if left.text.count != right.text.count {
                return left.text.count < right.text.count
            }
            return left.text.localizedCaseInsensitiveCompare(right.text) == .orderedDescending
        }) else {
            return hardFallback(title, maximumCharacters: maximumCharacters)
        }

        return best.text
    }

    private static func normalizedTitle(_ value: String) -> String {
        let normalized = AppleIntelligenceEventTitleRewriter.normalized(value)
        let trimCharacters = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\"“”‘’"))
        return normalized.trimmingCharacters(in: trimCharacters)
    }

    private static func tokenize(_ title: String) -> [Token] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = title
        tagger.setLanguage(.english, range: title.startIndex..<title.endIndex)

        var tokens: [Token] = []
        var searchStart = title.startIndex
        let end = title.endIndex
        for rawSubstring in title.split(whereSeparator: \.isWhitespace) {
            let rawValue = String(rawSubstring)
            guard let range = title.range(
                of: rawValue,
                range: searchStart ..< end
            ) else {
                continue
            }
            searchStart = range.upperBound

            let cleaned = cleanToken(rawValue)
            guard !cleaned.isEmpty,
                  cleaned.contains(where: \.isLetter) || cleaned.contains(where: \.isNumber) else {
                continue
            }
            tokens.append(
                Token(
                    text: cleaned,
                    identity: comparableIdentity(cleaned),
                    lexicalTag: tagger.tag(
                        at: range.lowerBound,
                        unit: .word,
                        scheme: .lexicalClass
                    ).0,
                    index: tokens.count
                )
            )
        }
        return tokens
    }

    private static func cleanToken(_ rawValue: String) -> String {
        let trimCharacters = CharacterSet.punctuationCharacters
            .union(.symbols)
            .subtracting(CharacterSet(charactersIn: "#@"))
        return rawValue.trimmingCharacters(in: trimCharacters)
    }

    private static func isProtected(_ token: Token, in tokens: [Token]) -> Bool {
        if EventTitleIntentGuard.isCoreIntent(token.text) {
            return true
        }
        if EventTitlePortableIdentifier.values(in: token.text).isEmpty == false {
            return true
        }
        if EventTitleSemanticSignals.isMeaningChanging(token.text) {
            return true
        }
        if token.text.contains(where: \.isNumber)
            || token.text.hasPrefix("#")
            || token.text.hasPrefix("@") {
            return true
        }

        let letters = token.text.filter(\.isLetter)
        let titleLetters = tokens.map { $0.text.filter(\.isLetter) }.joined()
        let titleIsMostlyUppercase = !titleLetters.isEmpty
            && titleLetters.filter(\.isUppercase).count * 5 >= titleLetters.count * 4
        return !titleIsMostlyUppercase
            && letters.count >= 2
            && letters.count <= 12
            && letters.allSatisfy(\.isUppercase)
    }

    private static func score(
        indices: [Int],
        tokens: [Token],
        protectedIndexes: Set<Int>,
        contextTokens: Set<String>,
        maximumCharacters: Int
    ) -> Int {
        let selected = Set(indices)
        var score = 0

        for index in indices {
            let token = tokens[index]
            let isGeneric = genericTerms.contains(token.identity)
            let isFunction = functionTags.contains(token.lexicalTag ?? .otherWord)
                || functionWords.contains(token.identity)

            if index == 0 { score += 22 }
            if index == tokens.count - 1 { score += 14 }
            if index >= max(0, tokens.count - 2) { score += 5 }
            if contextTokens.contains(token.identity) { score += 8 }
            if protectedIndexes.contains(index) { score += 27 }
            if isGeneric {
                score -= stronglyGenericTerms.contains(token.identity) ? 35 : 13
            }
            if isFunction { score -= 18 }

            if index > 0,
               token.text.first?.isUppercase == true,
               isNameIntroducingFunctionToken(tokens[index - 1]) {
                // A capitalized word after a name-introducing connector is often a person or
                // named subject. Preserve the complete lead phrase when it fits.
                score += 18
            }

            switch token.lexicalTag {
            case .noun, .adjective, .verb, .adverb, .organizationName, .personalName,
                 .placeName:
                score += 9
            case .conjunction, .determiner, .particle, .preposition, .pronoun:
                score -= 10
            default:
                break
            }
            if token.text.count <= 2, !protectedIndexes.contains(index) {
                score -= 4
            }
        }

        var transitions = 0
        var gaps = 0
        for pair in zip(indices, indices.dropFirst()) {
            if pair.1 == pair.0 + 1 {
                transitions += 1
                score += 18
            } else {
                gaps += 1
                score -= 22
            }
        }

        if indices.first == 0 { score += 26 }
        if indices.last == tokens.count - 1 { score += 8 }
        if indices.first == 0,
           indices.last != tokens.count - 1,
           containsAssociatedName(indices: indices, tokens: tokens) {
            score += 50
        }
        if indices.first != 0 {
            let containsFunctionWord = indices.contains { index in
                isFunctionToken(tokens[index])
            }
            score -= containsFunctionWord ? 28 : 14
        }
        score -= max(0, gaps - 1) * 4
        score += min(8, transitions * 2)

        let missingProtected = protectedIndexes.subtracting(selected).count
        score -= missingProtected * 7

        // Prefer a useful amount of the available budget, but do not let
        // length outrank intent or natural word boundaries.
        score += min(10, indices.map { tokens[$0].text.count }.reduce(0, +) / max(1, maximumCharacters / 10))
        return score
    }

    private static func isComplete(_ title: String) -> Bool {
        !title.isEmpty
            && !title.contains("…")
            && !title.hasSuffix("...")
            && !EventTitleSyntaxValidator.hasIncompleteTrailingPhrase(title)
    }

    private static func isFunctionToken(_ token: Token) -> Bool {
        functionTags.contains(token.lexicalTag ?? .otherWord)
            || functionWords.contains(token.identity)
    }

    private static func isNameIntroducingFunctionToken(_ token: Token) -> Bool {
        guard isFunctionToken(token) else { return false }
        return ["by", "via", "with"].contains(token.identity)
    }

    private static func containsAssociatedName(indices: [Int], tokens: [Token]) -> Bool {
        guard let firstIndex = indices.first else { return false }
        for index in indices where index > firstIndex {
            guard index > 0,
                  tokens[index].text.first?.isUppercase == true else {
                continue
            }
            if isNameIntroducingFunctionToken(tokens[index - 1]) {
                return true
            }
        }
        return false
    }

    private static func hardFallback(_ title: String, maximumCharacters: Int) -> String {
        // A misleading fragment is not a successful semantic rewrite.
        // Presentation applies ordinary visual truncation to the original.
        return title
    }

    private static func comparableIdentity(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
    }
}
