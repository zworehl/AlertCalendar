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
        let maximumCharacters = AppSettingsRules.normalizedEventTitleMaxCharacters(maximumCharacters)
        if let rewrittenTitle,
           let acceptedTitle = AppleIntelligenceEventTitleRewriter.acceptedTitle(
            rewrittenTitle,
            maximumCharacters: maximumCharacters
           ) {
            return acceptedTitle
        }

        return locallyTrimmedTitle(
            AppleIntelligenceEventTitleRewriter.normalized(originalTitle),
            maximumCharacters: maximumCharacters
        )
    }

    static func locallyTrimmedTitle(_ title: String, maximumCharacters: Int) -> String {
        let maximumCharacters = AppSettingsRules.normalizedEventTitleMaxCharacters(maximumCharacters)
        guard title.count > maximumCharacters else { return title }
        return String(title.prefix(maximumCharacters))
    }
}
