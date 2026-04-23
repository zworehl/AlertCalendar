import XCTest
@testable import AlertCalendar

final class MenuBarStateTests: XCTestCase {
    func testAllDayRangeFormattingKeepsMonthBeforeDayAcrossMonths() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent

        let startDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 22))!
        let endDay = calendar.date(from: DateComponents(year: 2026, month: 5, day: 5))!

        XCTAssertEqual(
            CalendarMonitor.formattedAllDayRange(
                startDay: startDay,
                lastInclusiveDay: endDay,
                calendar: calendar,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            "Apr 22-May 5"
        )
    }

    func testAllDayRangeFormattingKeepsCompactMonthSpanWithinSingleMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent

        let startDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 22))!
        let endDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 25))!

        XCTAssertEqual(
            CalendarMonitor.formattedAllDayRange(
                startDay: startDay,
                lastInclusiveDay: endDay,
                calendar: calendar,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            "Apr 22-25"
        )
    }

    func testFutureAllDayLabelUsesCountdownBeforeTheStartDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 23, hour: 10, minute: 0))!
        let startDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 24, hour: 0, minute: 0))!
        let endDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 0, minute: 0))!

        XCTAssertEqual(
            CalendarMonitor.allDayLabel(
                startDate: startDay,
                endDate: endDay,
                now: now,
                simplified: false,
                calendar: calendar
            ),
            "in 14h 0m"
        )
    }

    func testCurrentDayAllDayLabelStaysAllDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 23, hour: 10, minute: 0))!
        let startDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 23, hour: 0, minute: 0))!
        let endDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 24, hour: 0, minute: 0))!

        XCTAssertEqual(
            CalendarMonitor.allDayLabel(
                startDate: startDay,
                endDate: endDay,
                now: now,
                simplified: false,
                calendar: calendar
            ),
            "all-day"
        )
    }

    func testMenuBarRotationExcludesNextDayAllDayEventOutsideRotationWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 23, hour: 10, minute: 0))!
        let startDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 24, hour: 0, minute: 0))!
        let endDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 0, minute: 0))!
        let futureWindowEnd = now.addingTimeInterval(8 * 60 * 60)

        XCTAssertFalse(
            CalendarMonitor.shouldIncludeAllDayItemInMenuBarRotation(
                startDate: startDay,
                endDate: endDay,
                now: now,
                futureWindowEnd: futureWindowEnd,
                calendar: calendar
            )
        )
    }

    func testMenuBarRotationKeepsCurrentDayAllDayEventVisible() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 23, hour: 10, minute: 0))!
        let startDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 23, hour: 0, minute: 0))!
        let endDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 24, hour: 0, minute: 0))!
        let futureWindowEnd = now.addingTimeInterval(8 * 60 * 60)

        XCTAssertTrue(
            CalendarMonitor.shouldIncludeAllDayItemInMenuBarRotation(
                startDate: startDay,
                endDate: endDay,
                now: now,
                futureWindowEnd: futureWindowEnd,
                calendar: calendar
            )
        )
    }

    func testMenuBarEmptyStateTextUsesRotationWindowWhenLaterItemsExist() {
        XCTAssertEqual(
            CalendarMonitor.menuBarEmptyStateText(
                menuBarRotationWindowMinutes: 60,
                hasLaterItemsInDropdownWindow: true
            ),
            "No items in next 1h"
        )
    }

    func testMenuBarEmptyStateTextFallsBackToGenericEmptyStateWhenNothingElseExists() {
        XCTAssertEqual(
            CalendarMonitor.menuBarEmptyStateText(
                menuBarRotationWindowMinutes: 60,
                hasLaterItemsInDropdownWindow: false
            ),
            "No upcoming items"
        )
    }

    func testMenuBarRotationWindowDescriptionFormatsCompoundDurations() {
        XCTAssertEqual(
            CalendarMonitor.menuBarRotationWindowDescription(minutes: 90),
            "1h 30m"
        )
    }
}
