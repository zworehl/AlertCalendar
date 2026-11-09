import Foundation
import NaturalLanguage

/// English vocabulary shared by generation, local compaction and validation.
/// Names and identifiers remain Unicode data, with their original spelling.
enum EventTitleEnglishRules {
    static let abbreviations: [(word: String, short: String)] = [
        ("birthday", "Bday"), ("appointment", "Appt"),
        ("anniversary", "Anniv"), ("preparation", "Prep"),
    ]

    static func identity(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func canonical(_ value: String) -> String {
        let value = identity(value)
        return abbreviations.first { identity($0.short) == value }?.word ?? value
    }

    static func tokens(_ value: String) -> [String] {
        value.split { !$0.isLetter && !$0.isNumber }.map { canonical(String($0)) }
    }

    static func abbreviated(_ value: String) -> String {
        abbreviations.reduce(value) { result, entry in
            result.replacingOccurrences(
                of: "(?i)\\b" + entry.word + "\\b", with: entry.short, options: .regularExpression
            )
        }
    }

    /// This only rejects clearly unsupported prose; it never selects another
    /// language or translates. Short labels and proper names are inconclusive.
    static func supportsProse(_ value: String) -> Bool {
        guard tokens(value).count >= 3 else { return true }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(value)
        guard let language = recognizer.dominantLanguage, language != .english else { return true }
        return (recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0) < 0.85
    }

    static func supportsRewrite(_ candidate: String, source: String) -> Bool {
        // Short extracted names often resemble another language. The full
        // source provides stronger language evidence than a compact label.
        if Set(tokens(candidate)).isSubset(of: Set(tokens(source))), supportsProse(source) {
            return true
        }
        return supportsProse(candidate)
    }
}
