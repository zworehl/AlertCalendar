import Foundation
import XCTest
@testable import AlertCalendar

final class MenuBarBlinkAlertTests: AlertCalendarModelTestCase {
    func testBlinkingIsLimitedToConfiguredLeadTimeBeforeStart() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let event = makeUpcomingItem(
            id: "meeting",
            title: "Design review",
            startDate: start,
            endDate: start.addingTimeInterval(3600)
        )

        for leadMinutes in [1, 5, 15] {
            var settings = AppSettings.defaults
            settings.alertLeadMinutes = leadMinutes
            let leadSeconds = TimeInterval(leadMinutes * 60)
            let cases: [(offset: TimeInterval, shouldBlink: Bool)] = [
                (-leadSeconds - 1, false),
                (-leadSeconds, true),
                (-1, true),
                (0, false),
                (30, false),
                (1800, false),
                (3600, false),
            ]

            for testCase in cases {
                XCTAssertEqual(
                    CalendarMonitor.shouldBlinkForItem(
                        event,
                        now: start.addingTimeInterval(testCase.offset),
                        settings: settings
                    ),
                    testCase.shouldBlink,
                    "Lead time: \(leadMinutes)m; offset from start: \(testCase.offset)s"
                )
            }
        }
    }

    func testVehicleRestrictionDoesNotBlinkWithOneHourRemaining() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let restriction = makeUpcomingItem(
            id: "vehicle-restriction",
            title: "Vehicle restriction",
            startDate: now.addingTimeInterval(-12 * 3600),
            endDate: now.addingTimeInterval(3600)
        )

        XCTAssertTrue(CalendarMonitor.isActiveTimedEvent(restriction, now: now))
        XCTAssertFalse(CalendarMonitor.shouldBlinkForItem(restriction, now: now, settings: .defaults))
    }

    func testBlinkingCanBeDisabledBeforeAnEventStarts() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let event = makeUpcomingItem(
            id: "meeting",
            title: "Design review",
            startDate: now.addingTimeInterval(60),
            endDate: now.addingTimeInterval(3600)
        )
        var settings = AppSettings.defaults
        settings.enableBlinkAlert = false

        XCTAssertFalse(CalendarMonitor.shouldBlinkForItem(event, now: now, settings: settings))
    }
}
