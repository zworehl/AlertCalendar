import Foundation

enum FootballStatusText {
    private static let interruptedStatuses: [(badge: String, tokens: [String])] = [
        ("ABN", ["ABN", "ABANDONED"]),
        ("SUSP.", ["SUSP", "SUSPENDED"]),
        ("POSTP.", ["POSTP", "POSTPONED"]),
        ("DELAY", ["DELAY", "DELAYED"]),
        ("HYD.", ["HYDRATION", "COOLING", "WATER BREAK", "DRINKS BREAK", "DRINK BREAK"]),
        ("CANC.", ["CANCELED", "CANCELLED"]),
    ]

    static func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()
    }

    static func interruptedBadge(for normalizedStatus: String) -> String? {
        interruptedStatuses.first { entry in
            entry.tokens.contains { normalizedStatus.contains($0) }
        }?.badge
    }

    static func indicatesInterruptedPlay(_ normalizedStatus: String) -> Bool {
        interruptedBadge(for: normalizedStatus) != nil
    }
}
