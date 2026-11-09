import Foundation

struct EventBirthdayTitle {
    let name: String

    static func parse(_ title: String, knownBirthday: Bool = false) -> Self? {
        let title = AppleIntelligenceEventTitleRewriter.normalized(title)
        let pattern = #"(?i)^(.+?)(?:['’]s)?(?: \d+(?:st|nd|rd|th))? (?:birthday|bday)$"#
        var name: String?
        if let range = title.range(of: pattern, options: .regularExpression), range == title.startIndex..<title.endIndex {
            name = title.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
        } else if knownBirthday {
            name = title
        }
        guard let name, !name.isEmpty else { return nil }
        let words = EventTitleEnglishRules.tokens(name)
        let actions: Set<String> = [
            "buy", "gift", "plan", "planning", "prepare", "preparation", "party", "for", "of",
            "reminder", "celebrate", "celebration", "call", "send", "organize", "happy",
        ]
        guard !words.isEmpty, words.allSatisfy({ !actions.contains($0) }),
              name.allSatisfy({ $0.isLetter || $0.isWhitespace || "-'’.".contains($0) }) else { return nil }
        return Self(name: name)
    }

    var variants: [String] {
        var result = ["\(name) Birthday", "\(name) Bday"]
        var parts = name.split(whereSeparator: \.isWhitespace).map(String.init)
        // Abbreviate surnames before the given name, retaining every component.
        for index in parts.indices.reversed() {
            guard parts[index].lowercased() != "and" else { continue }
            if let initial = parts[index].first {
                parts[index] = "\(initial)."
                result.append(parts.joined(separator: " ") + " Bday")
            }
        }
        return result
    }

    func compactName(maximumCharacters: Int) -> String? {
        variants.map {
            $0.replacingOccurrences(of: #" (Birthday|Bday)$"#, with: "", options: .regularExpression)
        }.first { $0.count <= maximumCharacters }
    }

    func compact(maximumCharacters: Int, otherNames: [String] = []) -> String? {
        let competingVariants = Set(otherNames.filter { $0 != name }.flatMap {
            Self(name: $0).variants.map(EventTitleEnglishRules.identity)
        })
        return variants.first {
            $0.count <= maximumCharacters && !competingVariants.contains(EventTitleEnglishRules.identity($0))
        }
    }
}
