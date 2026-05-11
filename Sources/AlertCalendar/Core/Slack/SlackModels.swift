import Foundation

struct SlackStatusSyncRule: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var connectionID: String
    var calendarID: String
    var statusText: String
    var statusEmoji: String
    var isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case connectionID
        case calendarID
        case statusText
        case statusEmoji
        case isEnabled
    }

    init(
        id: String = UUID().uuidString,
        connectionID: String,
        calendarID: String,
        statusText: String = SlackMeetingStatus.defaultText,
        statusEmoji: String = SlackMeetingStatus.defaultEmoji,
        isEnabled: Bool
    ) {
        self.id = id
        self.connectionID = connectionID
        self.calendarID = calendarID
        self.statusText = statusText
        self.statusEmoji = statusEmoji
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        connectionID = try container.decodeIfPresent(String.self, forKey: .connectionID) ?? ""
        calendarID = try container.decodeIfPresent(String.self, forKey: .calendarID) ?? ""
        statusText = try container.decodeIfPresent(String.self, forKey: .statusText) ?? SlackMeetingStatus.defaultText
        statusEmoji = try container.decodeIfPresent(String.self, forKey: .statusEmoji) ?? SlackMeetingStatus.defaultEmoji
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
    }

    var isComplete: Bool {
        SlackConnection.normalizedValue(connectionID) != nil &&
            SlackConnection.normalizedValue(calendarID) != nil
    }

    static func pairKey(connectionID: String, calendarID: String) -> String {
        "\(connectionID)|\(calendarID)"
    }

    static func normalized(
        _ rules: [SlackStatusSyncRule],
        validConnectionIDs: Set<String>,
        validCalendarIDs: Set<String>? = nil
    ) -> [SlackStatusSyncRule] {
        var seenPairs: Set<String> = []
        var normalizedRules: [SlackStatusSyncRule] = []

        for rule in rules {
            guard let connectionID = SlackConnection.normalizedValue(rule.connectionID) else { continue }
            guard validConnectionIDs.contains(connectionID) else { continue }
            guard let calendarID = SlackConnection.normalizedValue(rule.calendarID) else { continue }
            if let validCalendarIDs, !validCalendarIDs.contains(calendarID) {
                continue
            }

            let pairKey = "\(connectionID)|\(calendarID)"
            guard seenPairs.insert(pairKey).inserted else { continue }

            normalizedRules.append(
                SlackStatusSyncRule(
                    id: SlackConnection.normalizedValue(rule.id) ?? UUID().uuidString,
                    connectionID: connectionID,
                    calendarID: calendarID,
                    statusText: SlackMeetingStatus.normalizedText(rule.statusText),
                    statusEmoji: SlackMeetingStatus.normalizedEmoji(rule.statusEmoji),
                    isEnabled: rule.isEnabled
                )
            )
        }

        return normalizedRules.sorted { lhs, rhs in
            let connectionOrder = lhs.connectionID.localizedCaseInsensitiveCompare(rhs.connectionID)
            if connectionOrder != .orderedSame {
                return connectionOrder == .orderedAscending
            }

            let calendarOrder = lhs.calendarID.localizedCaseInsensitiveCompare(rhs.calendarID)
            if calendarOrder != .orderedSame {
                return calendarOrder == .orderedAscending
            }

            return lhs.id < rhs.id
        }
    }

    static func firstAvailablePair(
        orderedConnectionIDs: [String],
        orderedCalendarIDs: [String],
        usedPairKeys: Set<String>,
        preferredConnectionID: String? = nil,
        preferredCalendarID: String? = nil
    ) -> (connectionID: String, calendarID: String)? {
        let normalizedConnectionIDs = orderedConnectionIDs.compactMap(SlackConnection.normalizedValue)
        let normalizedCalendarIDs = orderedCalendarIDs.compactMap(SlackConnection.normalizedValue)

        guard !normalizedConnectionIDs.isEmpty, !normalizedCalendarIDs.isEmpty else { return nil }

        let preferredConnectionID = SlackConnection.normalizedValue(preferredConnectionID)
        let preferredCalendarID = SlackConnection.normalizedValue(preferredCalendarID)
        var candidatePairs: [(String, String)] = []
        var seenCandidateKeys: Set<String> = []

        func appendCandidate(connectionID: String, calendarID: String) {
            let key = pairKey(connectionID: connectionID, calendarID: calendarID)
            guard seenCandidateKeys.insert(key).inserted else { return }
            candidatePairs.append((connectionID, calendarID))
        }

        if let preferredConnectionID, let preferredCalendarID {
            appendCandidate(connectionID: preferredConnectionID, calendarID: preferredCalendarID)
        }

        if let preferredConnectionID {
            for calendarID in normalizedCalendarIDs {
                appendCandidate(connectionID: preferredConnectionID, calendarID: calendarID)
            }
        }

        if let preferredCalendarID {
            for connectionID in normalizedConnectionIDs {
                appendCandidate(connectionID: connectionID, calendarID: preferredCalendarID)
            }
        }

        for connectionID in normalizedConnectionIDs {
            for calendarID in normalizedCalendarIDs {
                appendCandidate(connectionID: connectionID, calendarID: calendarID)
            }
        }

        for candidatePair in candidatePairs {
            let key = pairKey(connectionID: candidatePair.0, calendarID: candidatePair.1)
            if !usedPairKeys.contains(key) {
                return (candidatePair.0, candidatePair.1)
            }
        }

        return nil
    }

    static func uniquelyResolved(
        _ rules: [SlackStatusSyncRule],
        orderedConnectionIDs: [String],
        orderedCalendarIDs: [String]
    ) -> [SlackStatusSyncRule] {
        let validConnectionIDs = Set(orderedConnectionIDs.compactMap(SlackConnection.normalizedValue))
        let validCalendarIDs = Set(orderedCalendarIDs.compactMap(SlackConnection.normalizedValue))
        var usedPairKeys: Set<String> = []
        var resolvedRules: [SlackStatusSyncRule] = []

        for rule in rules {
            guard let connectionID = SlackConnection.normalizedValue(rule.connectionID) else { continue }
            guard validConnectionIDs.contains(connectionID) else { continue }
            guard let calendarID = SlackConnection.normalizedValue(rule.calendarID) else { continue }
            guard validCalendarIDs.contains(calendarID) else { continue }

            guard let resolvedPair = firstAvailablePair(
                orderedConnectionIDs: orderedConnectionIDs,
                orderedCalendarIDs: orderedCalendarIDs,
                usedPairKeys: usedPairKeys,
                preferredConnectionID: connectionID,
                preferredCalendarID: calendarID
            ) else {
                continue
            }

            let resolvedRule = SlackStatusSyncRule(
                id: SlackConnection.normalizedValue(rule.id) ?? UUID().uuidString,
                connectionID: resolvedPair.connectionID,
                calendarID: resolvedPair.calendarID,
                statusText: SlackMeetingStatus.normalizedText(rule.statusText),
                statusEmoji: SlackMeetingStatus.normalizedEmoji(rule.statusEmoji),
                isEnabled: rule.isEnabled
            )
            usedPairKeys.insert(pairKey(connectionID: resolvedPair.connectionID, calendarID: resolvedPair.calendarID))
            resolvedRules.append(resolvedRule)
        }

        return resolvedRules
    }
}

struct SlackConnection: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let teamID: String
    let teamName: String
    let workspaceURLString: String?
    let workspaceImageURLString: String?
    let userID: String
    let userName: String
    let userDisplayName: String?
    let emailAddress: String?
    let profileImageURLString: String?
    let connectedAt: Date
    let lastValidatedAt: Date

    init(
        id: String,
        teamID: String,
        teamName: String,
        workspaceURLString: String?,
        workspaceImageURLString: String? = nil,
        userID: String,
        userName: String,
        userDisplayName: String?,
        emailAddress: String?,
        profileImageURLString: String? = nil,
        connectedAt: Date,
        lastValidatedAt: Date
    ) {
        self.id = id
        self.teamID = teamID
        self.teamName = teamName
        self.workspaceURLString = workspaceURLString
        self.workspaceImageURLString = workspaceImageURLString
        self.userID = userID
        self.userName = userName
        self.userDisplayName = userDisplayName
        self.emailAddress = emailAddress
        self.profileImageURLString = profileImageURLString
        self.connectedAt = connectedAt
        self.lastValidatedAt = lastValidatedAt
    }

    var resolvedDisplayName: String {
        SlackConnection.normalizedValue(userDisplayName)
            ?? SlackConnection.normalizedValue(userName)
            ?? userID
    }

    var displayLabel: String {
        return "\(resolvedDisplayName) on \(teamName)"
    }

    var workspaceLabel: String {
        teamName
    }

    var secondaryLabel: String {
        "\(emailAddress ?? userName) • \(teamID)"
    }

    var profileImageURL: URL? {
        guard let profileImageURLString = SlackConnection.normalizedValue(profileImageURLString) else { return nil }
        return URL(string: profileImageURLString)
    }

    var workspaceImageURL: URL? {
        if let workspaceImageURLString = SlackConnection.normalizedValue(workspaceImageURLString) {
            return URL(string: workspaceImageURLString)
        }

        guard
            let workspaceURLString = SlackConnection.normalizedValue(workspaceURLString),
            let workspaceURL = URL(string: workspaceURLString)
        else {
            return nil
        }

        return workspaceURL.appending(path: "favicon.ico")
    }

    static func makeID(teamID: String, userID: String) -> String {
        "\(teamID)|\(userID)"
    }

    static func normalized(_ connections: [SlackConnection]) -> [SlackConnection] {
        var uniqueByID: [String: SlackConnection] = [:]

        for connection in connections {
            let normalized = SlackConnection(
                id: connection.id,
                teamID: connection.teamID,
                teamName: normalizedValue(connection.teamName) ?? connection.teamID,
                workspaceURLString: normalizedValue(connection.workspaceURLString),
                workspaceImageURLString: normalizedValue(connection.workspaceImageURLString),
                userID: connection.userID,
                userName: normalizedValue(connection.userName) ?? connection.userID,
                userDisplayName: normalizedValue(connection.userDisplayName),
                emailAddress: normalizedValue(connection.emailAddress),
                profileImageURLString: normalizedValue(connection.profileImageURLString),
                connectedAt: connection.connectedAt,
                lastValidatedAt: connection.lastValidatedAt
            )

            if let existing = uniqueByID[normalized.id] {
                if normalized.lastValidatedAt >= existing.lastValidatedAt {
                    uniqueByID[normalized.id] = normalized
                }
            } else {
                uniqueByID[normalized.id] = normalized
            }
        }

        return uniqueByID.values.sorted { lhs, rhs in
            let teamOrder = lhs.teamName.localizedCaseInsensitiveCompare(rhs.teamName)
            if teamOrder != .orderedSame {
                return teamOrder == .orderedAscending
            }

            let userOrder = lhs.displayLabel.localizedCaseInsensitiveCompare(rhs.displayLabel)
            if userOrder != .orderedSame {
                return userOrder == .orderedAscending
            }

            return lhs.id < rhs.id
        }
    }

    static func normalizedValue(_ rawValue: String?) -> String? {
        AlertCalendarString.trimmedNonEmpty(rawValue)
    }
}

struct SlackProfileStatusSnapshot: Codable, Equatable, Sendable {
    let statusText: String
    let statusEmoji: String
    let statusExpiration: Int

    var isEmpty: Bool {
        statusText.isEmpty && statusEmoji.isEmpty
    }

    var identity: SlackProfileStatusIdentity {
        SlackProfileStatusIdentity(text: statusText, emoji: statusEmoji)
    }
}

struct SlackProfileStatusIdentity: Equatable, Hashable, Sendable {
    let statusText: String
    let statusEmoji: String

    init(text: String?, emoji: String?) {
        statusText = SlackConnection.normalizedValue(text) ?? ""
        statusEmoji = SlackConnection.normalizedValue(emoji).map(SlackMeetingStatus.normalizedEmoji) ?? ""
    }
}

enum SlackMeetingStatus {
    static let defaultText = "In a meeting"
    static let defaultEmoji = "🗓️"

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
