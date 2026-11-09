import Foundation

/// Equivalence is deliberately narrow: an instruction to cancel is not a
/// canceled appointment, and a semifinal is not a final.
enum EventTitleSemanticSignals {
    static func isMeaningChanging(_ value: String) -> Bool {
        group(for: value) != nil
    }

    static func preserves(sourceTerm: String, candidateIdentities: Set<String>) -> Bool {
        let source = EventTitleEnglishRules.canonical(sourceTerm)
        return candidateIdentities.contains { candidate in
            let candidate = EventTitleEnglishRules.canonical(candidate)
            return source == candidate || (group(for: source) != nil && group(for: source) == group(for: candidate))
        }
    }

    static func group(for value: String) -> String? {
        let identity = EventTitleEnglishRules.canonical(value)
        return groups.first { $0.value.contains(identity) }?.key
    }

    private static let groups: [String: Set<String>] = [
        "not": ["not"], "no": ["no"], "never": ["never"], "without": ["without"],
        "cancel-action": ["cancel"], "cancellation": ["cancellation", "cancelation"],
        "canceled": ["canceled", "cancelled"],
        "reschedule-action": ["reschedule"], "rescheduled": ["rescheduled"],
        "postpone-action": ["postpone"], "postponed": ["postponed"],
        "delay-action": ["delay"], "delayed": ["delayed"],
        "tentative": ["tentative", "provisional"], "confirmed": ["confirmed"],
        "declined": ["declined", "rejected"], "overdue": ["overdue"],
        "unpaid": ["unpaid"], "paid": ["paid"], "failed": ["failed"],
        "blocked": ["blocked"], "optional": ["optional"], "mandatory": ["mandatory", "required"],
        "final": ["final", "finals"], "semifinal": ["semifinal", "semifinals"],
        "quarterfinal": ["quarterfinal", "quarterfinals"], "live": ["live"],
        "initial": ["initial"], "followup": ["followup"],
        "before": ["before"], "after": ["after"], "eve": ["eve"],
        "phase": ["phase"], "part": ["part"], "round": ["round"],
    ]
}
