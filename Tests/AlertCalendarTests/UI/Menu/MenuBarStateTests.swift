import Foundation
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

    func testAlertBlinkTextOpacityUsesWholeSecondParity() {
        XCTAssertEqual(
            CalendarMonitor.alertBlinkTextOpacity(now: Date(timeIntervalSince1970: 2)),
            1
        )
        XCTAssertEqual(
            CalendarMonitor.alertBlinkTextOpacity(now: Date(timeIntervalSince1970: 3)),
            0
        )
    }

    func testAlertBlinkTextOpacityDoesNotChangeWithinSameSecond() {
        let early = CalendarMonitor.alertBlinkTextOpacity(now: Date(timeIntervalSince1970: 10.1))
        let late = CalendarMonitor.alertBlinkTextOpacity(now: Date(timeIntervalSince1970: 10.9))

        XCTAssertEqual(early, late)
    }

    func testTimedEventNowSegmentShowsForFirstMinuteAfterStartWithoutMeetingURL() {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let event = makeTimedEvent(
            title: "Design review",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(30 * 60),
            meetingURL: nil
        )

        XCTAssertEqual(
            CalendarMonitor.timedEventNowMenuSegment(
                for: event,
                compactTitle: "Design review",
                now: startDate
            ),
            "Design review now"
        )
        XCTAssertEqual(
            CalendarMonitor.timedEventNowMenuSegment(
                for: event,
                compactTitle: "Design review",
                now: startDate.addingTimeInterval(59)
            ),
            "Design review now"
        )
    }

    func testTimedEventNowSegmentStopsAfterOneMinute() throws {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let meeting = makeTimedEvent(
            title: "Design review",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(30 * 60),
            meetingURL: try XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij"))
        )

        XCTAssertNil(
            CalendarMonitor.timedEventNowMenuSegment(
                for: meeting,
                compactTitle: "Design review",
                now: startDate.addingTimeInterval(60)
            )
        )
    }

    func testTimedEventNowStateIgnoresAllDayEvents() {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let allDayEvent = makeTimedEvent(
            title: "Design review",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(30 * 60),
            isAllDay: true,
            meetingURL: nil
        )

        XCTAssertFalse(
            CalendarMonitor.shouldShowTimedEventNowState(
                for: allDayEvent,
                now: startDate.addingTimeInterval(30)
            )
        )
    }

    func testOverdueReminderProgressIsFull() {
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        let reminder = makeReminder(
            title: "Submit expenses",
            dueDate: dueDate
        )

        XCTAssertNil(
            CalendarMonitor.activeItemProgress(
                for: reminder,
                now: dueDate.addingTimeInterval(-60),
                weekdayOnlyEventCalendarIDs: []
            )
        )
        XCTAssertEqual(
            CalendarMonitor.activeItemProgress(
                for: reminder,
                now: dueDate,
                weekdayOnlyEventCalendarIDs: []
            ),
            1
        )
        XCTAssertEqual(
            CalendarMonitor.activeItemProgress(
                for: reminder,
                now: dueDate.addingTimeInterval(60),
                weekdayOnlyEventCalendarIDs: []
            ),
            1
        )
    }

    func testAlertForItemIncludesAnyTimedEventFirstMinute() throws {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let event = makeTimedEvent(
            title: "Design review",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(30 * 60),
            meetingURL: nil
        )
        let now = startDate.addingTimeInterval(30)

        XCTAssertTrue(
            CalendarMonitor.shouldAlertForItem(
                event,
                now: now,
                leadSeconds: 5 * 60
            )
        )
        XCTAssertEqual(
            CalendarMonitor.alertDescription(for: event, now: now),
            "Design review starts now."
        )
    }

    private func makeTimedEvent(
        id: String = "event-1",
        title: String,
        startDate: Date,
        endDate: Date?,
        isAllDay: Bool = false,
        meetingURL: URL?
    ) -> UpcomingItem {
        UpcomingItem(
            id: id,
            title: title,
            date: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: meetingURL,
            calendarID: "calendar-1",
            calendarName: "Work",
            calendarColor: .systemBlue,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
    }

    private func makeReminder(
        id: String = "reminder-1",
        title: String,
        dueDate: Date
    ) -> UpcomingItem {
        UpcomingItem(
            id: id,
            title: title,
            date: dueDate,
            endDate: nil,
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: "reminders-1",
            calendarName: "Tasks",
            calendarColor: .systemOrange,
            kind: .reminder,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
    }
}
