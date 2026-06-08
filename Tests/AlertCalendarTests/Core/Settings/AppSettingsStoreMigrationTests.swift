import Foundation
import XCTest
@testable import AlertCalendar

final class AppSettingsStoreMigrationTests: XCTestCase {
    func testRegisterDefaultsRemovesLegacyFocusFilterState() {
        let suiteName = "AppSettingsStoreMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(Data([1, 2, 3]), forKey: "activeFocusCalendarFilterState")

        AppSettingsStore(defaults: defaults).registerDefaults()

        XCTAssertNil(defaults.object(forKey: "activeFocusCalendarFilterState"))
    }

    func testMeetingBrowserRoutingPersistsAsStructuredSettings() {
        let suiteName = "AppSettingsStoreMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = AppSettingsStore(defaults: defaults)
        store.registerDefaults()

        var settings = store.load()
        settings.meetingBrowserRouting = MeetingBrowserRoutingSettings(
            defaultRoute: MeetingBrowserRoute(browser: .chrome, profileID: "Default"),
            rules: [
                CalendarMeetingBrowserRule(
                    id: "rule-a",
                    name: "Work",
                    calendarIDs: ["cal-a", "cal-b"],
                    route: MeetingBrowserRoute(browser: .chrome, profileID: "Profile 3")
                ),
            ]
        )

        store.save(settings)

        let loaded = store.load().meetingBrowserRouting
        XCTAssertEqual(loaded.defaultRoute.browser, .chrome)
        XCTAssertEqual(loaded.defaultRoute.profileID, "Default")
        XCTAssertEqual(loaded.rules.map(\.id), ["rule-a"])
        XCTAssertEqual(loaded.rules.first?.calendarIDs, Set(["cal-a", "cal-b"]))
        XCTAssertEqual(loaded.rules.first?.route.profileID, "Profile 3")
    }
}
