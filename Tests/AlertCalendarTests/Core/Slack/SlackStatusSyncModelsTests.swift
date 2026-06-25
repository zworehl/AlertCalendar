import XCTest
@testable import AlertCalendar

final class SlackStatusSyncModelsTests: SlackStatusSyncTestCase {
    func testSlackStatusSyncRuleFirstAvailablePairSkipsUsedCombinations() {
        let pair = SlackStatusSyncRule.firstAvailablePair(
            orderedConnectionIDs: ["team-1|user-1", "team-2|user-2"],
            orderedCalendarIDs: ["calendar-a", "calendar-b"],
            usedPairKeys: [
                SlackStatusSyncRule.pairKey(connectionID: "team-1|user-1", calendarID: "calendar-a"),
                SlackStatusSyncRule.pairKey(connectionID: "team-1|user-1", calendarID: "calendar-b"),
            ],
            preferredConnectionID: "team-1|user-1",
            preferredCalendarID: "calendar-a"
        )

        XCTAssertEqual(pair?.connectionID, "team-2|user-2")
        XCTAssertEqual(pair?.calendarID, "calendar-a")
    }

    func testSlackStatusSyncRuleUniquelyResolvedKeepsRulesDistinct() {
        let rules = [
            SlackStatusSyncRule(
                id: "rule-1",
                connectionID: "team-1|user-1",
                calendarID: "calendar-a",
                statusText: "Alpha",
                statusEmoji: "🅰️",
                isEnabled: true
            ),
            SlackStatusSyncRule(
                id: "rule-2",
                connectionID: "team-1|user-1",
                calendarID: "calendar-a",
                statusText: "Beta",
                statusEmoji: "🅱️",
                isEnabled: false
            ),
        ]

        let resolvedRules = SlackStatusSyncRule.uniquelyResolved(
            rules,
            orderedConnectionIDs: ["team-1|user-1"],
            orderedCalendarIDs: ["calendar-a", "calendar-b"]
        )

        XCTAssertEqual(
            resolvedRules.map { "\($0.id)|\($0.connectionID)|\($0.calendarID)" },
            [
                "rule-1|team-1|user-1|calendar-a",
                "rule-2|team-1|user-1|calendar-b",
            ]
        )
    }

    func testSlackConnectionNormalizationKeepsMostRecentlyValidatedDuplicate() {
        let olderConnection = SlackConnection(
            id: "T1|U1",
            teamID: "T1",
            teamName: "Workspace",
            workspaceURLString: "https://workspace.slack.com/",
            userID: "U1",
            userName: "sam",
            userDisplayName: "Sam",
            emailAddress: "sam@example.com",
            connectedAt: Date(timeIntervalSince1970: 100),
            lastValidatedAt: Date(timeIntervalSince1970: 200)
        )
        let newerConnection = SlackConnection(
            id: "T1|U1",
            teamID: "T1",
            teamName: "Workspace",
            workspaceURLString: "https://workspace.slack.com/",
            userID: "U1",
            userName: "samuel",
            userDisplayName: "Samuel",
            emailAddress: "samuel@example.com",
            connectedAt: Date(timeIntervalSince1970: 100),
            lastValidatedAt: Date(timeIntervalSince1970: 400)
        )

        XCTAssertEqual(
            SlackConnection.normalized([olderConnection, newerConnection]),
            [newerConnection]
        )
    }

    func testSlackCredentialDecodingKeepsOlderOAuthBackupsReadable() throws {
        let payload = """
        {
          "authMethod": "oauthPKCE",
          "accessToken": "xoxe.xoxp-123",
          "refreshToken": "xoxe-1-refresh",
          "accessTokenExpiration": "2026-04-23T12:00:00Z",
          "clientID": "123.456",
          "grantedScopes": "users.profile:read,users.profile:write",
          "tokenType": "user"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let credential = try decoder.decode(SlackCredential.self, from: payload)

        XCTAssertEqual(credential.authMethod, .oauthPKCE)
        XCTAssertEqual(credential.accessToken, "xoxe.xoxp-123")
        XCTAssertEqual(credential.refreshToken, "xoxe-1-refresh")
    }

    func testSlackUserTokenExtractorFindsTokenInsideJSONPayload() {
        let payload = #"{"authed_user":{"access_token":"xoxe.xoxp-12345-abcdef"}} "#

        XCTAssertEqual(
            SlackUserTokenExtractor.firstToken(in: payload),
            "xoxe.xoxp-12345-abcdef"
        )
    }

    func testSlackStatusSyncRuleNormalizationDeduplicatesInvalidAndDuplicateRules() {
        let rules = [
            SlackStatusSyncRule(
                connectionID: "T1|U1",
                calendarID: "calendar-1",
                statusText: "In a workshop",
                statusEmoji: "🎙️",
                statusTextSource: .eventTitle,
                isEnabled: true
            ),
            SlackStatusSyncRule(
                connectionID: "T1|U1",
                calendarID: "calendar-1",
                statusText: "Duplicate",
                statusEmoji: "💬",
                isEnabled: false
            ),
            SlackStatusSyncRule(connectionID: "missing", calendarID: "calendar-2", isEnabled: true),
            SlackStatusSyncRule(connectionID: "T2|U2", calendarID: "missing", isEnabled: true),
        ]

        XCTAssertEqual(
            SlackStatusSyncRule.normalized(
                rules,
                validConnectionIDs: ["T1|U1", "T2|U2"],
                validCalendarIDs: ["calendar-1", "calendar-2"]
            ),
            [
                SlackStatusSyncRule(
                    id: rules[0].id,
                    connectionID: "T1|U1",
                    calendarID: "calendar-1",
                    statusText: "In a workshop",
                    statusEmoji: "🎙️",
                    statusTextSource: .eventTitle,
                    isEnabled: true
                ),
            ]
        )
    }

    func testSlackStatusSyncRuleDecodingDefaultsLegacyRulesToFixedText() throws {
        let payload = """
        {
          "id": "rule-1",
          "connectionID": "T1|U1",
          "calendarID": "calendar-1",
          "statusText": "Heads down",
          "statusEmoji": "🎯",
          "isEnabled": true
        }
        """.data(using: .utf8)!

        let rule = try JSONDecoder().decode(SlackStatusSyncRule.self, from: payload)

        XCTAssertEqual(rule.statusTextSource, .fixed)
    }

    func testSlackStatusSyncRuleNormalizationPreservesPriorityOrder() {
        let rules = [
            SlackStatusSyncRule(
                id: "low-alpha-id-but-second-priority",
                connectionID: "T1|U1",
                calendarID: "calendar-b",
                statusText: "Second",
                statusEmoji: "✌️",
                isEnabled: true
            ),
            SlackStatusSyncRule(
                id: "z-high-id-but-first-priority",
                connectionID: "T1|U1",
                calendarID: "calendar-a",
                statusText: "First",
                statusEmoji: "☝️",
                isEnabled: true
            ),
        ]

        let normalizedRules = SlackStatusSyncRule.normalized(
            rules,
            validConnectionIDs: ["T1|U1"],
            validCalendarIDs: ["calendar-a", "calendar-b"]
        )

        XCTAssertEqual(
            normalizedRules.map(\.id),
            [
                "low-alpha-id-but-second-priority",
                "z-high-id-but-first-priority",
            ]
        )
    }

    func testSlackMeetingStatusNormalizesKnownAliasesToPrettyEmoji() {
        XCTAssertEqual(SlackMeetingStatus.normalizedEmoji(":spiral_calendar_pad:"), "🗓️")
        XCTAssertEqual(SlackMeetingStatus.normalizedEmoji(":dog:"), "🐶")
        XCTAssertTrue(SlackMeetingStatus.looksLikeSlackAlias(":dog:"))
    }
}
