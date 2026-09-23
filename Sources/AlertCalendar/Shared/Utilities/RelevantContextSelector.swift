import Foundation

enum RelevantContextSelector {
    private struct Candidate {
        let index: Int
        let text: String
        let score: Int
    }

    private static let maximumSegmentCharacters = 360
    private static let minimumUsefulRemainder = 24

    static func selectedText(
        from rawValue: String?,
        referenceText: [String],
        maximumCharacters: Int,
        maximumSegments: Int
    ) -> String? {
        guard let rawValue = AlertCalendarString.trimmedNonEmpty(rawValue),
              maximumCharacters > 0,
              maximumSegments > 0 else {
            return nil
        }

        let segments = normalizedSegments(from: redacted(rawValue))
        guard !segments.isEmpty else { return nil }

        let completeText = segments.joined(separator: "\n")
        if completeText.count <= maximumCharacters,
           segments.count <= maximumSegments {
            return completeText
        }

        let referenceTokens = tokens(in: referenceText.joined(separator: " "))
        let candidates = segments.enumerated().map { index, segment in
            Candidate(
                index: index,
                text: segment,
                score: relevanceScore(
                    for: segment,
                    referenceTokens: referenceTokens,
                    position: index,
                    segmentCount: segments.count
                )
            )
        }
        let rankedCandidates = candidates.sorted { left, right in
            if left.score != right.score {
                return left.score > right.score
            }
            return left.index < right.index
        }

        var selected: [Candidate] = []
        var selectedIndexes: Set<Int> = []
        var usedCharacters = 0

        for candidate in rankedCandidates {
            guard selected.count < maximumSegments else { break }
            let separatorCharacters = selected.isEmpty ? 0 : 1
            let remainingCharacters = maximumCharacters - usedCharacters - separatorCharacters
            guard remainingCharacters >= minimumUsefulRemainder else { break }

            let boundedText = bounded(
                candidate.text,
                maximumCharacters: min(maximumSegmentCharacters, remainingCharacters)
            )
            guard boundedText.count >= minimumUsefulRemainder,
                  selectedIndexes.insert(candidate.index).inserted else {
                continue
            }
            selected.append(
                Candidate(index: candidate.index, text: boundedText, score: candidate.score)
            )
            usedCharacters += separatorCharacters + boundedText.count
        }

        return AlertCalendarString.trimmedNonEmpty(
            selected
                .sorted { $0.index < $1.index }
                .map(\.text)
                .joined(separator: "\n")
        )
    }

    static func relevanceScore(
        for value: String,
        referenceText: [String]
    ) -> Int {
        relevanceScore(
            for: value,
            referenceTokens: tokens(in: referenceText.joined(separator: " ")),
            position: 0,
            segmentCount: 1
        )
    }

    static func redacted(_ value: String) -> String {
        var result = value
        for (pattern, replacement) in redactionPatterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return result
    }

    private static func relevanceScore(
        for value: String,
        referenceTokens: Set<String>,
        position: Int,
        segmentCount: Int
    ) -> Int {
        let valueTokens = tokens(in: value)
        let overlapCount = valueTokens.intersection(referenceTokens).count
        var score = overlapCount * 100

        if let colonIndex = value.firstIndex(of: ":") {
            let fieldValue = value[value.index(after: colonIndex)...]
            let letterCount = fieldValue.count(where: \.isLetter)
            score += letterCount >= 3 ? 36 : 8
            if fieldValue.contains("[number]") && letterCount < 3 {
                score -= 28
            }
        }
        if value.count >= 20 && value.count <= 240 {
            score += 12
        }
        if isMostlyUppercase(value), !value.contains(":") {
            score -= 18
        }
        if position == 0 || position == segmentCount - 1 {
            score += 4
        }

        return score
    }

    private static func normalizedSegments(from value: String) -> [String] {
        let normalizedNewlines = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var segments: [String] = []
        var seen: Set<String> = []

        for rawLine in normalizedNewlines.components(separatedBy: "\n") {
            let line = normalizedWhitespace(rawLine)
            guard isInformative(line) else { continue }
            for segment in splitLongSegment(line) {
                let identity = comparableIdentity(segment)
                guard seen.insert(identity).inserted else { continue }
                segments.append(segment)
            }
        }

        return segments
    }

    private static func isInformative(_ value: String) -> Bool {
        let withoutPlaceholders = ["[link]", "[email]", "[number]", "[account]", "[path]"]
            .reduce(value) { partialResult, placeholder in
                partialResult.replacingOccurrences(of: placeholder, with: "")
            }
        return withoutPlaceholders.contains { $0.isLetter || $0.isNumber }
    }

    private static func splitLongSegment(_ value: String) -> [String] {
        guard value.count > maximumSegmentCharacters else { return [value] }

        var sentences: [String] = []
        value.enumerateSubstrings(
            in: value.startIndex..<value.endIndex,
            options: [.bySentences, .substringNotRequired]
        ) { _, range, _, _ in
            let sentence = normalizedWhitespace(String(value[range]))
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        if sentences.count > 1 {
            return sentences.flatMap(chunksByWords)
        }
        return chunksByWords(value)
    }

    private static func chunksByWords(_ value: String) -> [String] {
        let words = value.split(whereSeparator: \.isWhitespace).map(String.init)
        var chunks: [String] = []
        var current = ""

        for word in words {
            if current.isEmpty {
                current = bounded(word, maximumCharacters: maximumSegmentCharacters)
            } else if current.count + word.count + 1 <= maximumSegmentCharacters {
                current += " \(word)"
            } else {
                chunks.append(current)
                current = bounded(word, maximumCharacters: maximumSegmentCharacters)
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    private static func bounded(_ value: String, maximumCharacters: Int) -> String {
        guard value.count > maximumCharacters else { return value }
        let prefix = String(value.prefix(maximumCharacters))
        if let lastWhitespace = prefix.lastIndex(where: \.isWhitespace) {
            return String(prefix[..<lastWhitespace])
        }
        return prefix
    }

    private static func tokens(in value: String) -> Set<String> {
        Set(
            value
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .map(comparableIdentity)
                .filter { $0.count >= 3 && !stopWords.contains($0) }
        )
    }

    private static func normalizedWhitespace(_ value: String) -> String {
        value
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func comparableIdentity(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
    }

    private static func isMostlyUppercase(_ value: String) -> Bool {
        let letters = value.filter(\.isLetter)
        guard letters.count >= 8 else { return false }
        return letters.filter(\.isUppercase).count * 5 >= letters.count * 4
    }

    private static let redactionPatterns: [(String, String)] = [
        (#"(?i)\b(?:https?|ftp)://[^\s<>()]+"#, "[link]"),
        (#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "[email]"),
        (#"(?i)\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]){10,30}\b"#, "[account]"),
        (#"(?<!\d)(?:\d[\s-]?){9,}(?!\d)"#, "[number]"),
        (#"(?i)(?:/Users|/home)/[^\s]+"#, "[path]"),
    ]

    private static let stopWords: Set<String> = [
        "and", "con", "das", "del", "der", "des", "die", "ein", "for", "from",
        "las", "les", "los", "para", "por", "que", "the", "und", "une", "with",
    ]
}
