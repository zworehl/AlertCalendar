import Foundation

enum SlackMeetingStatus {
    static let defaultText = "In a meeting"
    static let defaultPreEventText = "Starting soon"
    static let defaultEmoji = "🗓️"
    static let defaultPreEventEmoji = "⏳"

    private static let friendlyEmojiAliases: [String: String] = [
        ":spiral_calendar_pad:": "🗓️",
        ":calendar:": "📅",
        ":spiral_notepad:": "🗒️",
        ":telephone_receiver:": "📞",
        ":phone:": "📞",
        ":laptop:": "💻",
        ":computer:": "💻",
        ":speech_balloon:": "💬",
        ":microphone:": "🎤",
        ":video_camera:": "📹",
        ":camera:": "📷",
        ":dog:": "🐶",
        ":cat:": "🐱",
    ]

    static func normalizedText(_ rawValue: String?) -> String {
        SlackConnection.normalizedValue(rawValue) ?? defaultText
    }

    static func normalizedPreEventText(_ rawValue: String?) -> String {
        SlackConnection.normalizedValue(rawValue) ?? defaultPreEventText
    }

    static func normalizedEmoji(_ rawValue: String?) -> String {
        guard let normalized = SlackConnection.normalizedValue(rawValue) else { return defaultEmoji }
        return friendlyEmojiAliases[normalized.lowercased()] ?? normalized
    }

    static func looksLikeSlackAlias(_ rawValue: String?) -> Bool {
        guard let normalized = SlackConnection.normalizedValue(rawValue) else { return false }
        return normalized.first == ":" && normalized.last == ":" && normalized.count > 2
    }

    static func snapshot(
        text: String?,
        emoji: String?,
        expirationTimestamp: Int
    ) -> SlackProfileStatusSnapshot {
        SlackProfileStatusSnapshot(
            statusText: normalizedText(text),
            statusEmoji: normalizedEmoji(emoji),
            statusExpiration: expirationTimestamp
        )
    }

    static func statusLine(text: String?, emoji: String?) -> String {
        let normalizedText = normalizedText(text)
        let normalizedEmoji = normalizedEmoji(emoji)
        return "\(normalizedEmoji) \(normalizedText)"
    }

    static func statusIdentity(text: String?, emoji: String?) -> SlackProfileStatusIdentity {
        SlackProfileStatusIdentity(
            text: normalizedText(text),
            emoji: normalizedEmoji(emoji)
        )
    }

    static func hasSameStatusIdentity(
        _ snapshot: SlackProfileStatusSnapshot,
        _ candidate: SlackProfileStatusSnapshot
    ) -> Bool {
        snapshot.identity == candidate.identity
    }

    static func hasStatusIdentity(
        _ snapshot: SlackProfileStatusSnapshot,
        matching candidate: SlackProfileStatusIdentity
    ) -> Bool {
        snapshot.identity == candidate
    }

    static func isLikelyManaged(
        _ snapshot: SlackProfileStatusSnapshot,
        matching candidate: SlackProfileStatusIdentity
    ) -> Bool {
        hasStatusIdentity(snapshot, matching: candidate) && snapshot.statusExpiration > 0
    }

    static func isManaged(
        _ snapshot: SlackProfileStatusSnapshot,
        managedSnapshot: SlackProfileStatusSnapshot?
    ) -> Bool {
        guard let managedSnapshot else { return false }
        return hasSameStatusIdentity(snapshot, managedSnapshot)
    }
}

enum SlackCredentialAuthMethod: String, Codable, Equatable, Sendable {
    case legacyUserToken
    case oauthPKCE
}

struct SlackCredential: Codable, Equatable, Sendable {
    let authMethod: SlackCredentialAuthMethod
    let accessToken: String
    let refreshToken: String?
    let accessTokenExpiration: Date?
    let clientID: String?
    let grantedScopes: String?
    let tokenType: String?

    static func legacyUserToken(_ token: String) -> SlackCredential {
        SlackCredential(
            authMethod: .legacyUserToken,
            accessToken: token,
            refreshToken: nil,
            accessTokenExpiration: nil,
            clientID: nil,
            grantedScopes: nil,
            tokenType: "user"
        )
    }
}

enum SlackStoredKeychainCredential: Equatable, Sendable {
    case legacyToken(String)
    case credential(SlackCredential)
}

enum SlackUserTokenExtractor {
    static func firstToken(in text: String) -> String? {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let pattern = #"xoxe\.xoxp-[A-Za-z0-9-]+|xoxp-[A-Za-z0-9-]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        guard let match = regex.firstMatch(in: text, options: [], range: fullRange) else { return nil }
        guard let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }
}
