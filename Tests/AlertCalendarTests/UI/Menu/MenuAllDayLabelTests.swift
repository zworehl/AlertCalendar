import Foundation
import XCTest
@testable import AlertCalendar

final class MenuAllDayLabelTests: XCTestCase {
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

    func testTomorrowAllDayLabelUsesCalendarDayInsteadOfHourCountdown() {
        let calendar = utcCalendar()
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 4, day: 23, hour: 22)
        )!
        let startDay = calendar.date(
            from: DateComponents(year: 2026, month: 4, day: 24)
        )!
        let endDay = calendar.date(
            from: DateComponents(year: 2026, month: 4, day: 25)
        )!

        XCTAssertEqual(
            CalendarMonitor.allDayLabel(
                startDate: startDay,
                endDate: endDay,
                now: now,
                simplified: false,
                calendar: calendar
            ),
            "tomorrow"
        )
    }

    func testLaterAllDayLabelKeepsCountdownOutsideTomorrow() {
        let calendar = utcCalendar()
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 4, day: 23, hour: 22)
        )!
        let startDay = calendar.date(
            from: DateComponents(year: 2026, month: 4, day: 25)
        )!
        let endDay = calendar.date(
            from: DateComponents(year: 2026, month: 4, day: 26)
        )!

        XCTAssertEqual(
            CalendarMonitor.allDayLabel(
                startDate: startDay,
                endDate: endDay,
                now: now,
                simplified: false,
                calendar: calendar
            ),
            "in 1d 2h 0m"
        )
    }

    func testCurrentDayAllDayLabelStaysAllDay() {
        let calendar = utcCalendar()
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 4, day: 23, hour: 10)
        )!
        let startDay = calendar.date(
            from: DateComponents(year: 2026, month: 4, day: 23)
        )!
        let endDay = calendar.date(
            from: DateComponents(year: 2026, month: 4, day: 24)
        )!

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

    func testTomorrowBirthdayMenuSegmentIncludesCalendarDay() {
        XCTAssertEqual(
            CalendarMonitor.allDayMenuSegment(
                compactTitle: "Ana's birthday",
                detail: "tomorrow",
                isBirthday: true
            ),
            "Ana's birthday tomorrow"
        )
        XCTAssertEqual(
            CalendarMonitor.allDayMenuSegment(
                compactTitle: "Ana's birthday",
                detail: "all-day",
                isBirthday: true
            ),
            "Ana's birthday"
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
