import Foundation
import XCTest
@testable import AlertCalendar

final class SlackStatusSyncPersistenceTests: SlackStatusSyncTestCase {
    func testAppleMusicSettingsAndCalendarPriorityPersist() throws {
        let suiteName = "SlackStatusSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let connection = SlackConnection(
            id: "T1|U1", teamID: "T1", teamName: "Workspace", workspaceURLString: nil,
            userID: "U1", userName: "sam", userDisplayName: nil, emailAddress: nil,
            connectedAt: Date(timeIntervalSince1970: 100), lastValidatedAt: Date(timeIntervalSince1970: 100)
        )
        var settings = AppSettings.defaults
        settings.slackConnections = [connection]
        settings.slackStatusSyncRules = [
            SlackStatusSyncRule(connectionID: connection.id, calendarID: "calendar-1", priority: 3, isEnabled: true),
        ]
        settings.appleMusicStatus = AppleMusicStatusSettings(
            isEnabled: true,
            connectionIDs: [connection.id, "missing"],
            priority: 7,
            source: .youtubeMusic
        )
        let store = AppSettingsStore(defaults: defaults)
        store.registerDefaults()
        store.save(settings)

        let loaded = store.load()
        XCTAssertEqual(loaded.slackStatusSyncRules.first?.priority, 3)
        XCTAssertEqual(loaded.appleMusicStatus.connectionIDs, [connection.id])
        XCTAssertEqual(loaded.appleMusicStatus.priority, 7)
        XCTAssertEqual(loaded.appleMusicStatus.source, .youtubeMusic)
        XCTAssertTrue(loaded.appleMusicStatus.isEnabled)
    }

    func testLegacyAppleMusicSettingsDefaultToAppleMusicSource() throws {
        let data = try XCTUnwrap(
            """
            {"isEnabled":true,"connectionIDs":[],"priority":6}
            """.data(using: .utf8)
        )

        let settings = try JSONDecoder().decode(AppleMusicStatusSettings.self, from: data)

        XCTAssertEqual(settings.source, .appleMusic)
    }

    func testAppSettingsStoreMigratesLegacySlackSelectionIntoStatusRule() {
        let suiteName = "SlackStatusSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

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
        defaults.set(try? JSONEncoder().encode([connection]), forKey: DefaultsKeys.slackConnections)
        defaults.set(true, forKey: DefaultsKeys.enableSlackMeetingStatusSync)
        defaults.set("calendar-1", forKey: DefaultsKeys.slackMeetingCalendarID)
        defaults.set(connection.id, forKey: DefaultsKeys.selectedSlackConnectionID)
        defaults.set("Deep work", forKey: DefaultsKeys.slackMeetingStatusText)
        defaults.set("🎯", forKey: DefaultsKeys.slackMeetingStatusEmoji)

        let settings = AppSettingsStore(defaults: defaults).load()

        XCTAssertEqual(settings.slackStatusSyncRules.count, 1)
        XCTAssertEqual(settings.slackStatusSyncRules.first?.connectionID, connection.id)
        XCTAssertEqual(settings.slackStatusSyncRules.first?.calendarID, "calendar-1")
        XCTAssertEqual(settings.slackStatusSyncRules.first?.statusText, "Deep work")
        XCTAssertEqual(settings.slackStatusSyncRules.first?.statusEmoji, "🎯")
        XCTAssertEqual(settings.slackStatusSyncRules.first?.isEnabled, true)
    }

    func testAppSettingsStorePersistsPreEventSlackRuleConfiguration() throws {
        let suiteName = "SlackStatusSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

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
        var settings = AppSettings.defaults
        settings.slackConnections = [connection]
        settings.slackStatusSyncRules = [
            SlackStatusSyncRule(
                connectionID: connection.id,
                calendarID: "calendar-1",
                startsBeforeEvent: true,
                leadMinutes: 15,
                preEventStatusText: "Wrapping up before the call",
                preEventStatusEmoji: "🔜",
                isEnabled: true
            ),
        ]

        let store = AppSettingsStore(defaults: defaults)
        store.registerDefaults()
        store.save(settings)

        let loadedRule = try XCTUnwrap(store.load().slackStatusSyncRules.first)
        XCTAssertTrue(loadedRule.startsBeforeEvent)
        XCTAssertEqual(loadedRule.leadMinutes, 15)
        XCTAssertEqual(loadedRule.preEventStatusText, "Wrapping up before the call")
        XCTAssertEqual(loadedRule.preEventStatusEmoji, "🔜")
    }
}
