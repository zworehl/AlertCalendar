import Foundation

extension AppleIntelligenceEventTitleRewriter {
    static func containsNovelAttachmentFieldLabel(
        _ candidate: String,
        request: EventTitleRewriteRequest
    ) -> Bool {
        let originalTokens = comparableSemanticTokens(in: request.title)
        let candidateTokens = comparableSemanticTokens(in: candidate)
            .subtracting(originalTokens)
        let labelTokens = Set(
            request.distinctiveContextFacts.flatMap { fact -> [String] in
                guard let colonIndex = fact.firstIndex(of: ":") else { return [] }
                return Array(comparableSemanticTokens(in: String(fact[..<colonIndex])))
            }
        )
        return !candidateTokens.intersection(labelTokens).isEmpty
    }

    static func distinctiveContextCoverageScore(
        _ candidate: String,
        request: EventTitleRewriteRequest
    ) -> Int {
        let originalTokens = comparableSemanticTokens(in: request.title)
        let candidateTokens = comparableSemanticTokens(in: candidate)
        var fieldLabelTokens: Set<String> = []
        let factValueTokens = Set(
            request.distinctiveContextFacts.flatMap { fact -> [String] in
                let value: String
                if let colonIndex = fact.firstIndex(of: ":") {
                    fieldLabelTokens.formUnion(
                        comparableSemanticTokens(in: String(fact[..<colonIndex]))
                    )
                    value = String(fact[fact.index(after: colonIndex)...])
                } else {
                    value = fact
                }
                return Array(comparableSemanticTokens(in: value))
            }
        )
        let distinctiveTokens = factValueTokens
            .subtracting(originalTokens)
            .subtracting(fieldLabelTokens)
        return candidateTokens.intersection(distinctiveTokens).count
    }

    private static func comparableSemanticTokens(in value: String) -> Set<String> {
        Set(
            value
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count >= 3 }
                .map { token in
                    let identity = comparableIdentity(for: token)
                    if identity.count >= 5, identity.hasSuffix("s") {
                        return String(identity.dropLast())
                    }
                    return identity
                }
        )
    }
}
