import Foundation

enum EventTitleRewriteResolver {
    static func shouldRequestRewrite(
        for originalTitle: String,
        maximumCharacters: Int
    ) -> Bool {
        let maximumCharacters = AppSettingsRules.normalizedEventTitleMaxCharacters(maximumCharacters)
        let normalizedTitle = AppleIntelligenceEventTitleRewriter.normalized(originalTitle)
        return !normalizedTitle.isEmpty && normalizedTitle.count > maximumCharacters
    }

    static func resolvedTitle(
        _ rewrittenTitle: String?,
        originalTitle: String,
        maximumCharacters: Int
    ) -> String {
        return resolvedTitle(
            rewrittenTitle,
            request: EventTitleRewriteRequest(
                title: originalTitle,
                maximumCharacters: maximumCharacters
            )
        )
    }

    static func resolvedTitle(
        _ rewrittenTitle: String?,
        request: EventTitleRewriteRequest
    ) -> String {
        if let rewrittenTitle,
           let acceptedTitle = AppleIntelligenceEventTitleRewriter.acceptedTitle(
            rewrittenTitle,
            for: request
           ) {
            return acceptedTitle
        }

        return semanticallyCompactedTitle(
            originalTitle: request.title,
            maximumCharacters: request.maximumCharacters,
            supportingText: [
                request.description,
                request.location,
                request.calendarName,
            ].compactMap { $0 } + request.distinctiveContextFacts
        )
    }

    static func semanticallyCompactedTitle(
        originalTitle: String,
        maximumCharacters: Int,
        supportingText: [String] = []
    ) -> String {
        EventTitleSemanticCompactor.compact(
            title: originalTitle,
            maximumCharacters: maximumCharacters,
            supportingText: supportingText
        )
    }

    static func locallyTrimmedTitle(_ title: String, maximumCharacters: Int) -> String {
        let maximumCharacters = AppSettingsRules.normalizedEventTitleMaxCharacters(maximumCharacters)
        guard title.count > maximumCharacters else { return title }
        let splitIndex = title.index(title.startIndex, offsetBy: maximumCharacters)
        let prefix = title[..<splitIndex]
        guard let lastCharacter = prefix.last,
              let nextCharacter = title[splitIndex...].first,
              lastCharacter.isLetter || lastCharacter.isNumber,
              nextCharacter.isLetter || nextCharacter.isNumber,
              let wordBoundary = prefix.lastIndex(where: { $0.isWhitespace }) else {
            return completeFallbackTitle(
                String(prefix).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let wordBoundedPrefix = prefix[..<wordBoundary]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return completeFallbackTitle(
            wordBoundedPrefix.isEmpty ? String(prefix) : wordBoundedPrefix
        )
    }

    private static func completeFallbackTitle(_ value: String) -> String {
        let completed = EventTitleSyntaxValidator.removingIncompleteTrailingPhrase(from: value)
        return completed.isEmpty ? value : completed
    }
}
