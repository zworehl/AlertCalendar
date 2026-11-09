import Foundation

/// A successful compact title is shared across surfaces. When no faithful
/// phrase fits, surfaces visually truncate the original and expose it in full.
struct EventTitlePresentation: Equatable, Sendable {
    let title: String
    let usesResolvedTitle: Bool
}

enum EventTitlePresentationResolver {
    static func resolve(
        originalTitle: String,
        rewrittenTitle: String?,
        maximumCharacters: Int,
        isEnabled: Bool,
        isBirthday: Bool,
        usesModelRewrite: Bool = true,
        otherBirthdayNames: [String] = []
    ) -> EventTitlePresentation {
        guard isEnabled else {
            return EventTitlePresentation(title: originalTitle, usesResolvedTitle: false)
        }
        let maximumCharacters = AppSettingsRules.normalizedEventTitleMaxCharacters(maximumCharacters)
        let title: String
        if let birthday = EventBirthdayTitle.parse(originalTitle, knownBirthday: isBirthday) {
            title = birthday.compact(maximumCharacters: maximumCharacters, otherNames: otherBirthdayNames)
                ?? originalTitle
        } else if EventTitleRewriteResolver.shouldRequestRewrite(for: originalTitle, maximumCharacters: maximumCharacters) {
            title = EventTitleRewriteResolver.resolvedTitle(
                usesModelRewrite ? rewrittenTitle : nil,
                originalTitle: originalTitle,
                maximumCharacters: maximumCharacters
            )
        } else {
            title = originalTitle
        }
        return EventTitlePresentation(title: title, usesResolvedTitle: title.count <= maximumCharacters)
    }

    /// Only used inside a visibly labeled Birthdays group.
    static func birthdayName(from title: String) -> String {
        EventBirthdayTitle.parse(title, knownBirthday: true)?.name ?? title
    }
}
