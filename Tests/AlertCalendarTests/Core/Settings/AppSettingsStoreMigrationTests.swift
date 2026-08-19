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

    func testFootballDisallowedGoalNotificationPreferencePersists() {
        let suiteName = "AppSettingsStoreMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = AppSettingsStore(defaults: defaults)
        store.registerDefaults()

        var settings = store.load()
        XCTAssertTrue(settings.enableFootballDisallowedGoalNotifications)

        settings.enableFootballDisallowedGoalNotifications = false
        store.save(settings)

        XCTAssertFalse(store.load().enableFootballDisallowedGoalNotifications)
    }

    func testAgendaSummaryDefaultsOnAndPersistsUserChoice() {
        let suiteName = "AppSettingsStoreMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = AppSettingsStore(defaults: defaults)
        store.registerDefaults()

        var settings = store.load()
        XCTAssertTrue(settings.showAgendaSummary)
        XCTAssertEqual(settings.agendaSummaryMaximumWords, 60)
        XCTAssertFalse(settings.useLinkedPagePreviewsInAgendaSummary)

        settings.showAgendaSummary = false
        settings.agendaSummaryMaximumWords = 100
        settings.useLinkedPagePreviewsInAgendaSummary = true
        store.save(settings)

        XCTAssertFalse(store.load().showAgendaSummary)
        XCTAssertEqual(store.load().agendaSummaryMaximumWords, 100)
        XCTAssertTrue(store.load().useLinkedPagePreviewsInAgendaSummary)
    }

    func testDropdownLimitsDefaultAndPersistUsingSupportedSteps() {
        let suiteName = "AppSettingsStoreMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = AppSettingsStore(defaults: defaults)
        store.registerDefaults()

        var settings = store.load()
        XCTAssertEqual(settings.lookAheadHours, 24)
        XCTAssertEqual(settings.maxListItems, 10)

        settings.lookAheadHours = 700
        settings.maxListItems = 98
        store.save(settings)

        XCTAssertEqual(store.load().lookAheadHours, 720)
        XCTAssertEqual(store.load().maxListItems, 100)
    }

    func testAppleIntelligenceTitleRewriteDefaultsToMenuBarOnlyAndPersistsScope() {
        let suiteName = "AppSettingsStoreMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = AppSettingsStore(defaults: defaults)
        store.registerDefaults()

        var settings = store.load()
        XCTAssertFalse(settings.rewriteEventTitlesWithAppleIntelligence)
        XCTAssertFalse(settings.useRewrittenEventTitlesInDropdown)

        settings.rewriteEventTitlesWithAppleIntelligence = true
        settings.useRewrittenEventTitlesInDropdown = true
        store.save(settings)

        XCTAssertTrue(store.load().rewriteEventTitlesWithAppleIntelligence)
        XCTAssertTrue(store.load().useRewrittenEventTitlesInDropdown)
    }

    func testNonWorkingDatesPruneExpiredAndOutOfRangeConfiguration() {
        let suiteName = "AppSettingsStoreMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 10))!
        defaults.set(
            [
                "2026-07-05",
                "2026-07-06",
                "2026-07-11",
                "2026-08-03",
                "not-a-date",
            ],
            forKey: DefaultsKeys.nonWorkingDateKeys
        )

        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.nonWorkingDateKeys(now: now), ["2026-07-06"])
        XCTAssertEqual(defaults.stringArray(forKey: DefaultsKeys.nonWorkingDateKeys), ["2026-07-06"])
    }
}
