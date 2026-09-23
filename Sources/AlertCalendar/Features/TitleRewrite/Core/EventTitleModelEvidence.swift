import Foundation

extension AppleIntelligenceEventTitleRewriter {
    /// Rejects a fluent model answer that has no lexical evidence in the
    /// original item or its bounded, relevance-selected context. This is
    /// intentionally conservative: a single-token or purely generic source
    /// cannot provide enough evidence to reject a valid paraphrase.
    static func hasSemanticEvidence(
        _ candidate: String,
        request: EventTitleRewriteRequest
    ) -> Bool {
        let candidateTokens = semanticEvidenceTokens(in: candidate)
        guard !candidateTokens.isEmpty else { return false }

        let sourceText = [
            request.title,
            request.description,
            request.location,
            request.calendarName,
        ].compactMap { $0 } + request.distinctiveContextFacts
        let sourceTokens = Set(sourceText.flatMap { semanticEvidenceTokens(in: $0) })
        let specificSourceTokens = sourceTokens.subtracting(genericEvidenceTerms)
        guard specificSourceTokens.count >= 2 else { return true }

        return !candidateTokens
            .subtracting(genericEvidenceTerms)
            .isDisjoint(with: specificSourceTokens)
    }

    private static func semanticEvidenceTokens(in value: String) -> Set<String> {
        Set(
            value
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count >= 3 }
                .map(EventTitleEnglishRules.canonical)
        )
    }

    private static var genericEvidenceTerms: Set<String> {
        [
            "activity", "appointment", "calendar", "call", "chat", "connect", "discussion",
            "event", "gathering", "invite", "invitation", "meeting", "reminder", "review",
            "session", "sync", "task", "plan", "planning", "schedule", "scheduled",
            "annual", "monthly", "series", "weekly", "the", "and", "for", "with",
            "from", "into", "about",
        ]
    }
}
