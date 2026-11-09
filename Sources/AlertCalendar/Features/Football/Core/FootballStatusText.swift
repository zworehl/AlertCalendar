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
    private static let penaltyShootoutTokens: Set<String> = [
        "KFTM",
        "PEN",
        "PENALTY",
        "PENALTIES",
        "PENS",
        "PK",
        "PKS",
        "PSO",
        "SHOOTOUT",
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

    static func indicatesPenaltyShootout(_ normalizedStatus: String) -> Bool {
        let tokens = normalizedStatus
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)

        if tokens.contains(where: { penaltyShootoutTokens.contains($0) }) {
            return true
        }

        let compact = normalizedStatus
            .replacingOccurrences(of: #"[^A-Z0-9]+"#, with: "", options: .regularExpression)

        guard !compact.isEmpty else { return false }
        if penaltyShootoutTokens.contains(compact) {
            return true
        }

        return compact.contains("PENALTY")
            || compact.contains("PENALTIES")
            || compact.contains("SHOOTOUT")
    }
}
