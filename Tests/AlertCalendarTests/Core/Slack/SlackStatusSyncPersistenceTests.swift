import Foundation
import XCTest
@testable import AlertCalendar

final class SlackStatusSyncPersistenceTests: SlackStatusSyncTestCase {
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
