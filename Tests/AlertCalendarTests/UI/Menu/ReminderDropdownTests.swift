import Foundation
import XCTest
@testable import AlertCalendar

final class ReminderDropdownTests: XCTestCase {
    func testDateOnlyRemindersStayInTheDropdownWindowWithoutBecomingTimedItems() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 23, hour: 10))!
        let today = calendar.startOfDay(for: now)
        let futureWindowEnd = now.addingTimeInterval(24 * 60 * 60)
        let reminder = makeReminder(
            title: "Buy groceries",
            dueDate: today,
            hasExplicitTime: false
        )

        XCTAssertTrue(
            MenuContentView.shouldIncludeInDropdownTimeWindow(
                reminder,
                now: now,
                futureWindowEnd: futureWindowEnd
            )
        )
        XCTAssertTrue(
            CalendarMonitor.shouldIncludeInDropdownPreviewWindow(
                reminder,
                now: now,
                futureWindowEnd: futureWindowEnd
            )
        )
        XCTAssertFalse(CalendarMonitor.shouldIncludeTimedItemInMenuBarRotation(
            reminder,
            now: now,
            futureWindowSeconds: 60 * 60
        ))
    }

    func testDateOnlyRemindersAreOrderedAfterTimedItemsOnTheSameDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let day = calendar.date(from: DateComponents(year: 2026, month: 4, day: 23))!
        let timedReminder = makeReminder(
            id: "timed",
            title: "Timed reminder",
            dueDate: day.addingTimeInterval(9 * 60 * 60)
        )
        let dateOnlyReminder = makeReminder(
            id: "date-only",
            title: "Date-only reminder",
            dueDate: day,
            hasExplicitTime: false
        )

        let sorted = [dateOnlyReminder, timedReminder].sorted {
            UpcomingItem.sortPrecedes($0, $1)
        }

        XCTAssertEqual(sorted.map(\.id), ["timed", "date-only"])
    }

    func testDateOnlyReminderUsesItsDateBeforeLaterDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 4, day: 23))!
        let lateToday = makeReminder(
            id: "late-today",
            title: "Late today",
            dueDate: today.addingTimeInterval(23 * 60 * 60)
        )
        let tomorrow = makeReminder(
            id: "tomorrow",
            title: "Tomorrow",
            dueDate: calendar.date(byAdding: .day, value: 1, to: today)!,
            hasExplicitTime: false
        )

        let sorted = [tomorrow, lateToday].sorted {
            UpcomingItem.sortPrecedes($0, $1)
        }

        XCTAssertEqual(sorted.map(\.id), ["late-today", "tomorrow"])
    }

    func testReminderWithLinkShowsOpenLinkAction() {
        let reminder = makeReminder(
            title: "Read article",
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            openLinkURL: URL(string: "https://example.com/article")
        )

        XCTAssertTrue(MenuContentView.hasOpenLinkAction(for: reminder))
    }

    func testDateOnlyRemindersDoNotTriggerTimeBasedAlerts() {
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        let reminder = makeReminder(
            title: "Review list",
            dueDate: dueDate,
            hasExplicitTime: false
        )

        XCTAssertFalse(
            CalendarMonitor.shouldAlertForItem(
                reminder,
                now: dueDate.addingTimeInterval(-5 * 60),
                leadSeconds: 15 * 60
            )
        )
    }

    func testDateOnlyReminderProgressFillsThroughoutItsDueDay() throws {
        let calendar = utcCalendar()
        let dueDay = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 8)
        ))
        let reminder = makeReminder(
            title: "Pay water bill",
            dueDate: dueDay,
            hasExplicitTime: false
        )

        XCTAssertNil(CalendarMonitor.activeItemProgress(
            for: reminder,
            now: dueDay.addingTimeInterval(-1),
            calendar: calendar
        ))

        for (hours, expectedProgress) in [(0.0, 0.0), (6, 0.25), (12, 0.5), (18, 0.75), (24, 1), (48, 1)] {
            let progress = try XCTUnwrap(CalendarMonitor.activeItemProgress(
                for: reminder,
                now: dueDay.addingTimeInterval(hours * 60 * 60),
                calendar: calendar
            ))
            XCTAssertEqual(progress, expectedProgress, accuracy: 0.0001)
        }
    }

    func testDateOnlyReminderProgressUsesLocalDayBoundariesAcrossDaylightSavingChanges() throws {
        var calendar = utcCalendar()
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

        for (month, day, noonProgress) in [(3, 8, 11.0 / 23), (11, 1, 13.0 / 25)] {
            let dueDay = try XCTUnwrap(calendar.date(
                from: DateComponents(year: 2026, month: month, day: day)
            ))
            let noon = try XCTUnwrap(calendar.date(
                from: DateComponents(year: 2026, month: month, day: day, hour: 12)
            ))
            let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: dueDay))
            let reminder = makeReminder(title: "Review list", dueDate: dueDay, hasExplicitTime: false)

            XCTAssertEqual(
                try XCTUnwrap(CalendarMonitor.activeItemProgress(for: reminder, now: noon, calendar: calendar)),
                noonProgress,
                accuracy: 0.0001
            )
            XCTAssertLessThan(
                try XCTUnwrap(CalendarMonitor.activeItemProgress(
                    for: reminder, now: nextDay.addingTimeInterval(-1), calendar: calendar
                )),
                1
            )
            XCTAssertEqual(CalendarMonitor.activeItemProgress(for: reminder, now: nextDay, calendar: calendar), 1)
        }
    }

    func testDateOnlyReminderUsesCalendarRelativeDateInsteadOfMidnight() {
        let calendar = utcCalendar()
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 4, day: 23, hour: 10)
        )!

        let cases: [(DateComponents, String)] = [
            (DateComponents(year: 2026, month: 4, day: 23), "today"),
            (DateComponents(year: 2026, month: 4, day: 24), "tomorrow"),
            (DateComponents(year: 2026, month: 4, day: 22), "1 day ago"),
            (DateComponents(year: 2026, month: 4, day: 16), "1 week ago"),
            (DateComponents(year: 2026, month: 3, day: 23), "1 month ago")
        ]

        for (components, expectedText) in cases {
            let dueDate = calendar.date(from: components)!
            let reminder = makeReminder(
                title: "Review list",
                dueDate: dueDate,
                hasExplicitTime: false
            )

            XCTAssertEqual(
                MenuContentView.reminderScheduleText(
                    for: reminder,
                    now: now,
                    simplified: true,
                    timedText: "12:00 AM",
                    calendar: calendar
                ),
                expectedText
            )
        }
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeReminder(
        id: String = "reminder-1",
        title: String,
        dueDate: Date,
        hasExplicitTime: Bool = true,
        openLinkURL: URL? = nil
    ) -> UpcomingItem {
        UpcomingItem(
            id: id,
            title: title,
            date: dueDate,
            endDate: nil,
            isAllDay: false,
            hasExplicitTime: hasExplicitTime,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            openLinkURL: openLinkURL,
            calendarID: "reminders-1",
            calendarName: "Tasks",
            calendarColor: .systemOrange,
            kind: .reminder,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
    }
}
