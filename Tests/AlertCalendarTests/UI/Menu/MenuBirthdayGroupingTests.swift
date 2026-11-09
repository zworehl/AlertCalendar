import Foundation
import XCTest
@testable import AlertCalendar

final class MenuBirthdayGroupingTests: XCTestCase {
    func testBirthdaysOnSameDayCollapseIntoOneQueueEntry() throws {
        let calendar = utcCalendar()
        let birthdayDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 8))
        )
        let meetingDate = birthdayDate.addingTimeInterval(12 * 60 * 60)
        let birthdays = [
            item(id: "ana", title: "Ana", date: birthdayDate, calendarID: "birthdays"),
            item(id: "luis", title: "Luis", date: birthdayDate, calendarID: "birthdays"),
            item(id: "sofia", title: "Sofía", date: birthdayDate, calendarID: "birthdays"),
        ]
        let meeting = item(
            id: "meeting",
            title: "Design review",
            date: meetingDate,
            calendarID: "work",
            isAllDay: false
        )

        let entries = MenuContentView.upcomingQueueEntries(
            from: [birthdays[0], meeting, birthdays[1], birthdays[2]],
            birthdayCalendarIDs: ["birthdays"],
            calendar: calendar
        )

        XCTAssertEqual(entries.count, 2)
        guard case .birthdayGroup(let group) = entries[0] else {
            return XCTFail("Expected the first queue entry to be a birthday group")
        }
        XCTAssertEqual(group.items.map(\.title), ["Ana", "Luis", "Sofía"])
        XCTAssertEqual(MenuContentView.birthdayGroupTitle(itemCount: group.items.count), "3 birthdays")
        XCTAssertEqual(MenuContentView.birthdayGroupNames(group), "Ana · Luis · Sofía")
        guard case .item(let ungroupedMeeting) = entries[1] else {
            return XCTFail("Expected the meeting to remain an individual queue entry")
        }
        XCTAssertEqual(ungroupedMeeting.id, meeting.id)
    }

    func testSingleBirthdayKeepsItsIndividualQueueEntry() throws {
        let calendar = utcCalendar()
        let date = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 8))
        )
        let birthday = item(id: "ana", title: "Ana", date: date, calendarID: "birthdays")

        let entries = MenuContentView.upcomingQueueEntries(
            from: [birthday],
            birthdayCalendarIDs: ["birthdays"],
            calendar: calendar
        )

        XCTAssertEqual(entries.count, 1)
        guard case .item(let ungroupedBirthday) = entries[0] else {
            return XCTFail("Expected a single birthday to stay ungrouped")
        }
        XCTAssertEqual(ungroupedBirthday.id, birthday.id)
    }

    func testBirthdaysOnDifferentDaysDoNotCollapseTogether() throws {
        let calendar = utcCalendar()
        let firstDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 8))
        )
        let secondDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: firstDate))

        let entries = MenuContentView.upcomingQueueEntries(
            from: [
                item(id: "ana", title: "Ana", date: firstDate, calendarID: "birthdays"),
                item(id: "luis", title: "Luis", date: secondDate, calendarID: "birthdays"),
            ],
            birthdayCalendarIDs: ["birthdays"],
            calendar: calendar
        )

        XCTAssertEqual(entries.count, 2)
        for entry in entries {
            guard case .item = entry else {
                return XCTFail("Expected birthdays on separate days to stay ungrouped")
            }
        }
    }

    func testExpandedBirthdayTitleExtractsNameWithinLabeledGroup() {
        XCTAssertEqual(
            MenuContentView.compactBirthdayTitle("Carlos Angulo’s 32nd Birthday"),
            "Carlos Angulo"
        )
        XCTAssertEqual(
            MenuContentView.compactBirthdayTitle("Birthday planning"),
            "Birthday planning"
        )
    }

    func testBirthdayGroupChevronOnlyAppearsOnHover() {
        XCTAssertFalse(MenuContentView.birthdayGroupShowsChevron(isHovered: false))
        XCTAssertTrue(MenuContentView.birthdayGroupShowsChevron(isHovered: true))
    }

    func testTomorrowBirthdayGroupUsesCalendarDayText() throws {
        let calendar = utcCalendar()
        let startDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 8))
        )
        let endDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: startDate))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 12))
        )

        XCTAssertEqual(
            MenuContentView.birthdayGroupTimingText(
                startDate: startDate,
                endDate: endDate,
                now: now,
                simplified: false,
                calendar: calendar
            ),
            "tomorrow"
        )
        XCTAssertEqual(
            MenuContentView.birthdayGroupTimingText(
                startDate: startDate,
                endDate: endDate,
                now: now,
                simplified: true,
                calendar: calendar
            ),
            "tomorrow"
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func item(
        id: String,
        title: String,
        date: Date,
        calendarID: String,
        isAllDay: Bool = true
    ) -> UpcomingItem {
        UpcomingItem(
            id: id,
            title: title,
            date: date,
            endDate: isAllDay ? date.addingTimeInterval(24 * 60 * 60) : date.addingTimeInterval(60 * 60),
            isAllDay: isAllDay,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: calendarID,
            calendarName: calendarID,
            calendarColor: .systemPink,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
    }
}
