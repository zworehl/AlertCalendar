import Foundation
import XCTest
@testable import AlertCalendar

final class SlackAPIClientTests: SlackStatusSyncTestCase {
    func testSlackUserTokenConnectionAcceptsAuthTestIDsFromSlack() async throws {
        let session = makeMockSession { request in
            switch request.url?.path {
            case "/api/auth.test":
                return try self.jsonResponse(
                    for: request,
                    body: [
                        "ok": true,
                        "url": "https://zilkertrail.slack.com/",
                        "team": "Zilker Trail",
                        "team_id": "T04F46T1FB2",
                        "user": "jonn",
                        "user_id": "U07H0CVHWHZ",
                    ]
                )
            case "/api/users.profile.get":
                return try self.jsonResponse(
                    for: request,
                    body: [
                        "ok": true,
                        "profile": [
                            "display_name": "Jonn",
                            "real_name": "Jonnathan Rodriguez",
                            "image_192": "https://avatars.slack-edge.com/jonn-192.png",
                            "status_text": "",
                            "status_emoji": "",
                            "status_expiration": 0,
                        ],
                    ]
                )
            case "/api/team.info":
                return try self.jsonResponse(
                    for: request,
                    body: [
                        "ok": true,
                        "team": [
                            "id": "T04F46T1FB2",
                            "name": "Zilker Trail",
                            "icon": [
                                "image_88": "https://a.slack-edge.com/zilker-88.png",
                            ],
                        ],
                    ]
                )
            default:
                throw URLError(.badURL)
            }
        }

        let tokenStore = SlackTokenKeychainStore(
            service: "com.zworehl.alertcalendar.tests.slack.\(UUID().uuidString)"
        )
        let client = SlackAPIClient(session: session, tokenStore: tokenStore)

        let connection = try await client.connectUserToken("xoxp-123456")

        XCTAssertEqual(connection.teamID, "T04F46T1FB2")
        XCTAssertEqual(connection.teamName, "Zilker Trail")
        XCTAssertEqual(connection.userID, "U07H0CVHWHZ")
        XCTAssertEqual(connection.userName, "jonn")
        XCTAssertEqual(connection.userDisplayName, "Jonn")
        XCTAssertEqual(connection.id, "T04F46T1FB2|U07H0CVHWHZ")
        XCTAssertEqual(connection.profileImageURLString, "https://avatars.slack-edge.com/jonn-192.png")
        XCTAssertEqual(connection.workspaceImageURLString, "https://a.slack-edge.com/zilker-88.png")

        try? tokenStore.removeToken(for: connection.id)
    }

    func testSlackProfileSetUsesSnakeCaseStatusKeys() async throws {
        let expectedSnapshot = SlackProfileStatusSnapshot(
            statusText: "In a meeting",
            statusEmoji: "🗓️",
            statusExpiration: 1_776_919_500
        )
        let session = makeMockSession { request in
            switch request.url?.path {
            case "/api/users.profile.set":
                let body = try XCTUnwrap(self.requestBodyData(from: request))
                let payload = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: body) as? [String: Any]
                )
                let profile = try XCTUnwrap(payload["profile"] as? [String: Any])

                XCTAssertEqual(profile["status_text"] as? String, expectedSnapshot.statusText)
                XCTAssertEqual(profile["status_emoji"] as? String, expectedSnapshot.statusEmoji)
                XCTAssertEqual(profile["status_expiration"] as? Int, expectedSnapshot.statusExpiration)
                XCTAssertNil(profile["statusText"])
                XCTAssertNil(profile["statusEmoji"])
                XCTAssertNil(profile["statusExpiration"])

                return try self.jsonResponse(
                    for: request,
                    body: [
                        "ok": true,
                        "profile": [
                            "status_text": expectedSnapshot.statusText,
                            "status_emoji": ":spiral_calendar_pad:",
                            "status_expiration": expectedSnapshot.statusExpiration,
                        ],
                    ]
                )
            default:
                throw URLError(.badURL)
            }
        }

        let tokenStore = SlackTokenKeychainStore(
            service: "com.zworehl.alertcalendar.tests.slack.\(UUID().uuidString)"
        )
        let connection = SlackConnection(
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
        try tokenStore.saveToken("xoxp-123456", for: connection.id)

        let client = SlackAPIClient(session: session, tokenStore: tokenStore)
        let appliedSnapshot = try await client.setStatus(expectedSnapshot, for: connection)

        XCTAssertEqual(
            appliedSnapshot,
            SlackProfileStatusSnapshot(
                statusText: expectedSnapshot.statusText,
                statusEmoji: ":spiral_calendar_pad:",
                statusExpiration: expectedSnapshot.statusExpiration
            )
        )

        try? tokenStore.removeToken(for: connection.id)
    }

    func testSlackProfileSetReusesCachedTokenAfterInitialKeychainRead() async throws {
        let expectedSnapshot = SlackProfileStatusSnapshot(
            statusText: "Rotating status",
            statusEmoji: "📺",
            statusExpiration: 1_782_507_300
        )
        let session = makeMockSession { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer xoxp-cached-token")
            switch request.url?.path {
            case "/api/users.profile.set":
                return try self.jsonResponse(
                    for: request,
                    body: [
                        "ok": true,
                        "profile": [
                            "status_text": expectedSnapshot.statusText,
                            "status_emoji": expectedSnapshot.statusEmoji,
                            "status_expiration": expectedSnapshot.statusExpiration,
                        ],
                    ]
                )
            default:
                throw URLError(.badURL)
            }
        }

        let tokenStore = SlackTokenKeychainStore(
            service: "com.zworehl.alertcalendar.tests.slack.\(UUID().uuidString)"
        )
        let connection = SlackConnection(
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
        try tokenStore.saveToken("xoxp-cached-token", for: connection.id)

        let client = SlackAPIClient(session: session, tokenStore: tokenStore)
        let firstSnapshot = try await client.setStatus(expectedSnapshot, for: connection)
        try tokenStore.removeToken(for: connection.id)
        let secondSnapshot = try await client.setStatus(expectedSnapshot, for: connection)

        XCTAssertEqual(firstSnapshot, expectedSnapshot)
        XCTAssertEqual(secondSnapshot, expectedSnapshot)
    }
}
