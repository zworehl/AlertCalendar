import Foundation
import NaturalLanguage

enum EventTitleSyntaxValidator {
    private static let incompleteTrailingTags: Set<NLTag> = [
        .conjunction,
        .determiner,
        .particle,
        .preposition,
    ]

    static func hasIncompleteTrailingPhrase(_ value: String) -> Bool {
        guard let lastToken = lexicalTokens(in: value).last else { return false }
        return lastToken.tag.map(incompleteTrailingTags.contains) ?? false
    }

    static func dropsTrailingModifierObject(_ candidate: String, source: String) -> Bool {
        let candidateWords = EventTitleEnglishRules.tokens(candidate)
        let sourceWords = EventTitleEnglishRules.tokens(source)
        guard let lastWord = candidateWords.last,
              !EventTitleSemanticSignals.isMeaningChanging(lastWord),
              !EventTitleIntentGuard.isCoreIntent(lastWord),
              !["review", "plan", "planning", "call", "training"].contains(lastWord) else { return false }
        // Only judge an extracted fragment in source order; a model may
        // legitimately turn "Review the product" into "Product review".
        var matchedWords = 0
        for word in sourceWords where matchedWords < candidateWords.count {
            if word == candidateWords[matchedWords] { matchedWords += 1 }
        }
        guard matchedWords == candidateWords.count else { return false }

        let normalizedSource = normalized(source)
        let sourceTokens = lexicalTokens(in: normalizedSource)
        let matchingPositions = sourceTokens.indices.filter {
            EventTitleEnglishRules.canonical(String(normalizedSource[sourceTokens[$0].range])) == lastWord
        }
        guard matchingPositions.count == 1, let index = matchingPositions.first,
              index + 1 < sourceTokens.count else { return false }
        let suffix = String(normalizedSource[sourceTokens[index].range.lowerBound...])
        let suffixTokens = lexicalTokens(in: suffix)
        guard let tag = suffixTokens.first?.tag, tag == .adjective || tag == .verb else { return false }
        return true
    }

    static func removingIncompleteTrailingPhrase(from value: String) -> String {
        var result = normalized(value)

        while true {
            let tokens = lexicalTokens(in: result)
            guard tokens.count > 1,
                  let lastToken = tokens.last,
                  lastToken.tag.map(incompleteTrailingTags.contains) == true else {
                return result
            }

            result = String(result[..<lastToken.range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        }
    }

    private static func lexicalTokens(in value: String) -> [(range: Range<String.Index>, tag: NLTag?)] {
        let value = normalized(value)
        guard !value.isEmpty else { return [] }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = value
        tagger.setLanguage(.english, range: value.startIndex..<value.endIndex)
        var tokens: [(Range<String.Index>, NLTag?)] = []
        tagger.enumerateTags(
            in: value.startIndex..<value.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            tokens.append((range, tag))
            return true
        }
        return tokens
    }

    private static func normalized(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
