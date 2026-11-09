import Foundation

enum EventTitleIntentGuard {
    static func isCoreIntent(_ value: String) -> Bool {
        protectedIdentities.contains(EventTitleEnglishRules.canonical(value))
    }

    private static let protectedIdentities: Set<String> = [
        "appointment", "booking", "deadline", "delivery", "dropoff", "exam", "flight",
        "interview", "payment", "pickup", "renewal", "reservation", "test", "visit",
        "birthday", "anniversary", "wedding", "retirement", "preparation", "prep",
        "gift", "renew", "submit", "buy", "pay", "collect", "return", "send",
        "pick", "drop", "prepare",
    ]
}
