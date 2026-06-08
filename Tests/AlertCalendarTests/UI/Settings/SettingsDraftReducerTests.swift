import XCTest
@testable import AlertCalendar

final class SettingsDraftReducerTests: XCTestCase {
    func testAppliedSettingsNormalizesDependentWindowsAndCoordinates() {
        var draft = SettingsDraft(settings: .defaults)
        draft.lookAheadHours = 4
        draft.contextualPreviewLeadMinutes = 194
        draft.menuBarRotationWindowMinutes = 110
        draft.astronomyLatitude = 18.1234567
        draft.astronomyLongitude = -66.7654321

        let settings = draft.applied(
            to: .defaults,
            availableEventCalendarIDs: []
        )

        XCTAssertEqual(settings.lookAheadHours, 4)
        XCTAssertEqual(settings.contextualPreviewLeadMinutes, 180)
        XCTAssertEqual(settings.menuBarRotationWindowMinutes, 120)
        XCTAssertEqual(settings.astronomyLatitude, 18.12)
        XCTAssertEqual(settings.astronomyLongitude, -66.77)
    }

    func testAppliedSettingsNormalizesSlackRulesAgainstKnownConnectionsAndCalendars() {
        let connection = SlackConnection(
            id: "conn-a",
            teamID: "team-a",
            teamName: "Team",
            workspaceURLString: nil,
            userID: "user-a",
            userName: "user",
            userDisplayName: nil,
            emailAddress: nil,
            connectedAt: Date(timeIntervalSince1970: 1),
            lastValidatedAt: Date(timeIntervalSince1970: 1)
        )
        var baseSettings = AppSettings.defaults
        baseSettings.slackConnections = [connection]

        var draft = SettingsDraft(settings: baseSettings)
        draft.slackStatusSyncRules = [
            SlackStatusSyncRule(id: "rule-a", connectionID: "conn-a", calendarID: "cal-a", isEnabled: true),
            SlackStatusSyncRule(id: "rule-b", connectionID: "conn-a", calendarID: "missing-cal", isEnabled: true),
            SlackStatusSyncRule(id: "rule-c", connectionID: "missing-conn", calendarID: "cal-a", isEnabled: true),
        ]

        let settings = draft.applied(
            to: baseSettings,
            availableEventCalendarIDs: ["cal-a"]
        )

        XCTAssertEqual(settings.slackStatusSyncRules.map(\.id), ["rule-a"])
        XCTAssertEqual(settings.slackStatusSyncRules.first?.connectionID, "conn-a")
        XCTAssertEqual(settings.slackStatusSyncRules.first?.calendarID, "cal-a")
    }

    func testAppliedSettingsNormalizesMeetingBrowserRulesAgainstKnownCalendars() {
        var draft = SettingsDraft(settings: .defaults)
        draft.meetingBrowserRouting = MeetingBrowserRoutingSettings(
            defaultRoute: MeetingBrowserRoute(browser: .chrome, profileID: ""),
            rules: [
                CalendarMeetingBrowserRule(
                    id: "rule-a",
                    name: "Work",
                    calendarIDs: ["cal-a", "missing"],
                    route: MeetingBrowserRoute(browser: .chrome, profileID: "Profile 3")
                ),
                CalendarMeetingBrowserRule(
                    id: "rule-b",
                    name: "Missing",
                    calendarIDs: ["missing"],
                    route: MeetingBrowserRoute(browser: .safari)
                ),
            ]
        )

        let settings = draft.applied(
            to: .defaults,
            availableEventCalendarIDs: ["cal-a"]
        )

        XCTAssertEqual(settings.meetingBrowserRouting.defaultRoute.browser, .chrome)
        XCTAssertEqual(settings.meetingBrowserRouting.defaultRoute.profileID, "Default")
        XCTAssertEqual(settings.meetingBrowserRouting.rules.map(\.id), ["rule-a"])
        XCTAssertEqual(settings.meetingBrowserRouting.rules.first?.calendarIDs, Set(["cal-a"]))
    }
}
