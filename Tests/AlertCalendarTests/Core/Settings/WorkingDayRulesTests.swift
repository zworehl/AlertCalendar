import XCTest
@testable import AlertCalendar

final class WorkingDayRulesTests: XCTestCase {
    func testNormalizedNonWorkingDateKeysKeepsOnlySelectableWeekdays() {
        let calendar = gregorianCalendar()
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 10))!

        let normalized = WorkingDayRules.normalizedNonWorkingDateKeys(
            [
                "2026-07-05",
                "2026-07-06",
                "2026-07-11",
                "2026-08-03",
                "not-a-date",
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(normalized, ["2026-07-06"])
    }

    func testWorkingDurationSkipsConfiguredNonWorkingWeekday() {
        let calendar = gregorianCalendar()
        let mondayMorning = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 9))!
        let wednesdayMorning = calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 9))!
        let rules = WorkingDayRules(nonWorkingDateKeys: ["2026-07-07"], calendar: calendar)

        XCTAssertEqual(
            rules.workingDuration(from: mondayMorning, to: wednesdayMorning),
            24 * 60 * 60,
            accuracy: 0.001
        )
    }

    func testSelectableCalendarGridStartsOnSundayAndUsesCompleteWeeks() {
        let calendar = gregorianCalendar()
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 10))!

        let gridDates = WorkingDayRules.selectableCalendarGridDates(now: now, calendar: calendar)

        XCTAssertEqual(gridDates.count % 7, 0)
        XCTAssertEqual(gridDates.first.map { calendar.component(.weekday, from: $0) }, 1)
        XCTAssertEqual(gridDates.first.map { WorkingDayRules.dateKey(for: $0, calendar: calendar) }, "2026-07-05")
        XCTAssertEqual(gridDates.last.map { WorkingDayRules.dateKey(for: $0, calendar: calendar) }, "2026-08-08")
        XCTAssertEqual(
            Set(WorkingDayRules.selectableDateKeys(now: now, calendar: calendar)).contains("2026-07-06"),
            false
        )
    }

    private func gregorianCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
