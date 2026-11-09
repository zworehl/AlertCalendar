import Foundation

/// Ordinals are optional only in a recognized anniversary phrase. The kind
/// (wedding/work) and all named people remain part of every candidate.
struct EventAnniversaryTitle {
    let name: String
    let kind: String?

    static func parse(_ title: String) -> Self? {
        let pattern = #"(?i)^(.+?)(?:['’]s)?(?: \d+(?:st|nd|rd|th))? (?:(wedding|work) )?(?:anniversary|anniv)$"#
        let title = AppleIntelligenceEventTitleRewriter.normalized(title)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let nameRange = Range(match.range(at: 1), in: title) else { return nil }
        let name = String(title[nameRange])
        guard EventBirthdayTitle.parse(name, knownBirthday: true) != nil else { return nil }
        let kind = Range(match.range(at: 2), in: title).map { String(title[$0]).capitalized }
        return Self(name: name, kind: kind)
    }

    var variants: [String] {
        let label = [kind, "Anniversary"].compactMap { $0 }.joined(separator: " ")
        let shortLabel = [kind, "Anniv"].compactMap { $0 }.joined(separator: " ")
        let name = name.replacingOccurrences(of: " and ", with: " & ", options: .caseInsensitive)
        // Names stay intact here; unlike birthday metadata, ordinary calendar
        // anniversaries have no reliable roster for resolving initial collisions.
        return ["\(name) \(label)", "\(name) \(shortLabel)"]
    }

    func compact(maximumCharacters: Int) -> String? {
        variants.first { $0.count <= maximumCharacters }
    }
}
