import XCTest
@testable import AlertCalendar

@MainActor
final class MenuContentTimeFormattingTests: XCTestCase {
    func testTimedRangeOnSameDayUsesTimeOnly() {
        let calendar = utcCalendar()
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: 22, minute: 25))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: 23, minute: 25))!

        let text = MenuContentView.timeRangeText(
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            calendar: calendar,
            timeText: stubTimeText(startDate: startDate, endDate: endDate),
            dateTimeText: stubDateTimeText(startDate: startDate, endDate: endDate)
        )

        XCTAssertEqual(text, "start time-end time")
    }

    func testTimedRangeAcrossDaysUsesDateAndTime() {
        let calendar = utcCalendar()
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: 23, minute: 25))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 4, hour: 23, minute: 25))!

        let text = MenuContentView.timeRangeText(
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            calendar: calendar,
            timeText: stubTimeText(startDate: startDate, endDate: endDate),
            dateTimeText: stubDateTimeText(startDate: startDate, endDate: endDate)
        )

        XCTAssertEqual(text, "start date time-end date time")
    }

    func testTimedClockTextAcrossDaysUsesDateForBothEndpoints() {
        let calendar = utcCalendar()
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: 23, minute: 25))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 4, hour: 23, minute: 25))!
        let dateTimeText = stubDateTimeText(startDate: startDate, endDate: endDate)

        XCTAssertEqual(
            MenuContentView.timedEventClockText(
                date: startDate,
                startDate: startDate,
                endDate: endDate,
                calendar: calendar,
                timeText: stubTimeText(startDate: startDate, endDate: endDate),
                dateTimeText: dateTimeText
            ),
            "start date time"
        )
        XCTAssertEqual(
            MenuContentView.timedEventClockText(
                date: endDate,
                startDate: startDate,
                endDate: endDate,
                calendar: calendar,
                timeText: stubTimeText(startDate: startDate, endDate: endDate),
                dateTimeText: dateTimeText
            ),
            "end date time"
        )
    }

    func testDateTimeTextUsesMonthDayTimeOrder() {
        let calendar = utcCalendar()
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 23, minute: 25))!
        let previousLocale = MenuContentView.menuDateTimeFormatter.locale
        let previousTimeZone = MenuContentView.menuDateTimeFormatter.timeZone
        defer {
            MenuContentView.menuDateTimeFormatter.locale = previousLocale
            MenuContentView.menuDateTimeFormatter.timeZone = previousTimeZone
        }

        MenuContentView.menuDateTimeFormatter.locale = Locale(identifier: "en_US_POSIX")
        MenuContentView.menuDateTimeFormatter.timeZone = TimeZone(secondsFromGMT: 0)!

        XCTAssertEqual(MenuContentView.dateTimeText(date), "Jul 2 23:25")
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func stubTimeText(startDate: Date, endDate: Date) -> @MainActor @Sendable (Date) -> String {
        { date in
            date == startDate ? "start time" : "end time"
        }
    }

    private func stubDateTimeText(startDate: Date, endDate: Date) -> @MainActor @Sendable (Date) -> String {
        { date in
            date == startDate ? "start date time" : "end date time"
        }
    }
}
