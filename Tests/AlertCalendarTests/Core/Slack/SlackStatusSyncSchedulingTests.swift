import XCTest
@testable import AlertCalendar

final class SlackStatusSyncSchedulingTests: SlackStatusSyncTestCase {
    func testSlackMeetingStatusExpirationUsesLatestEndAcrossSelectedCalendar() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let selectedCalendarID = "work-calendar"
        let items = [
            makeEvent(
                id: "first",
                title: "Standup",
                calendarID: selectedCalendarID,
                startDate: now.addingTimeInterval(-10 * 60),
                endDate: now.addingTimeInterval(20 * 60)
            ),
            makeEvent(
                id: "second",
                title: "Planning",
                calendarID: selectedCalendarID,
                startDate: now.addingTimeInterval(-5 * 60),
                endDate: now.addingTimeInterval(55 * 60)
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.slackMeetingStatusExpirationTimestamp(
                for: items,
                calendarID: selectedCalendarID,
                now: now
            ),
            Int(now.addingTimeInterval(55 * 60).timeIntervalSince1970)
        )
    }

    func testSlackMeetingStatusExpirationIgnoresAllDayAndOtherCalendars() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let selectedCalendarID = "work-calendar"
        let items = [
            makeEvent(
                id: "other",
                title: "Other Team",
                calendarID: "different-calendar",
                startDate: now.addingTimeInterval(-15 * 60),
                endDate: now.addingTimeInterval(30 * 60)
            ),
            makeEvent(
                id: "all-day",
                title: "Conference",
                calendarID: selectedCalendarID,
                startDate: now.addingTimeInterval(-2 * 60 * 60),
                endDate: now.addingTimeInterval(5 * 60 * 60),
                isAllDay: true
            ),
        ]

        XCTAssertNil(
            CalendarMonitor.slackMeetingStatusExpirationTimestamp(
                for: items,
                calendarID: selectedCalendarID,
                now: now
            )
        )
    }

    func testActiveSlackRuleStateKeepsStatusAliveAcrossOverlappingMeetings() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let connectionID = "T1|U1"
        let rules = [
            SlackStatusSyncRule(
                connectionID: connectionID,
                calendarID: "calendar-1",
                statusText: "Heads down",
                statusEmoji: "🎯",
                isEnabled: true
            ),
            SlackStatusSyncRule(
                connectionID: connectionID,
                calendarID: "calendar-2",
                statusText: "In a meeting",
                statusEmoji: "🗓️",
                isEnabled: true
            ),
        ]
        let items = [
            makeEvent(
                id: "first",
                title: "Planning",
                calendarID: "calendar-1",
                startDate: now.addingTimeInterval(-15 * 60),
                endDate: now.addingTimeInterval(20 * 60)
            ),
            makeEvent(
                id: "second",
                title: "Review",
                calendarID: "calendar-2",
                startDate: now.addingTimeInterval(-5 * 60),
                endDate: now.addingTimeInterval(50 * 60)
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.activeSlackRuleStateByConnectionID(
                for: items,
                rules: rules,
                now: now
            ),
            [
                connectionID: CalendarMonitor.SlackActiveRuleState(
                    statusText: "Heads down",
                    statusEmoji: "🎯",
                    expiration: Int(now.addingTimeInterval(50 * 60).timeIntervalSince1970)
                ),
            ]
        )
    }

    func testActiveSlackRuleStateUsesRemainingMeetingAfterSkippedOverlapDropsOut() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let connectionID = "T1|U1"
        let rules = [
            SlackStatusSyncRule(
                connectionID: connectionID,
                calendarID: "calendar-1",
                statusText: "In a meeting",
                statusEmoji: "🗓️",
                isEnabled: true
            ),
        ]

        let remainingVisibleItems = [
            makeEvent(
                id: "still-active",
                title: "1:1",
                calendarID: "calendar-1",
                startDate: now.addingTimeInterval(-3 * 60),
                endDate: now.addingTimeInterval(35 * 60)
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.activeSlackRuleStateByConnectionID(
                for: remainingVisibleItems,
                rules: rules,
                now: now
            ),
            [
                connectionID: CalendarMonitor.SlackActiveRuleState(
                    statusText: "In a meeting",
                    statusEmoji: "🗓️",
                    expiration: Int(now.addingTimeInterval(35 * 60).timeIntervalSince1970)
                ),
            ]
        )
    }

    func testNextSlackStatusSyncTransitionDateUsesCurrentMeetingEndWhenAppOpensMidMeeting() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let rules = [
            SlackStatusSyncRule(
                connectionID: "T1|U1",
                calendarID: "calendar-1",
                isEnabled: true
            ),
        ]
        let meetingEnd = now.addingTimeInterval(18 * 60)
        let items = [
            makeEvent(
                id: "active",
                title: "Active meeting",
                calendarID: "calendar-1",
                startDate: now.addingTimeInterval(-12 * 60),
                endDate: meetingEnd
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.nextSlackStatusSyncTransitionDate(
                for: items,
                rules: rules,
                now: now
            ),
            meetingEnd
        )
    }

    func testNextSlackStatusSyncTransitionDateUsesOverlapStartBeforeCurrentMeetingEnds() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let rules = [
            SlackStatusSyncRule(
                connectionID: "T1|U1",
                calendarID: "calendar-1",
                isEnabled: true
            ),
            SlackStatusSyncRule(
                connectionID: "T1|U1",
                calendarID: "calendar-2",
                isEnabled: true
            ),
        ]
        let overlappingStart = now.addingTimeInterval(10 * 60)
        let items = [
            makeEvent(
                id: "current",
                title: "Current",
                calendarID: "calendar-1",
                startDate: now.addingTimeInterval(-20 * 60),
                endDate: now.addingTimeInterval(30 * 60)
            ),
            makeEvent(
                id: "overlap",
                title: "Overlap",
                calendarID: "calendar-2",
                startDate: overlappingStart,
                endDate: now.addingTimeInterval(55 * 60)
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.nextSlackStatusSyncTransitionDate(
                for: items,
                rules: rules,
                now: now
            ),
            overlappingStart
        )
    }

    func testNextSlackStatusSyncTransitionDateUsesSharedBoundaryForConsecutiveMeetings() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let rules = [
            SlackStatusSyncRule(
                connectionID: "T1|U1",
                calendarID: "calendar-1",
                isEnabled: true
            ),
        ]
        let sharedBoundary = now.addingTimeInterval(25 * 60)
        let items = [
            makeEvent(
                id: "first",
                title: "First",
                calendarID: "calendar-1",
                startDate: now.addingTimeInterval(-15 * 60),
                endDate: sharedBoundary
            ),
            makeEvent(
                id: "second",
                title: "Second",
                calendarID: "calendar-1",
                startDate: sharedBoundary,
                endDate: now.addingTimeInterval(50 * 60)
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.nextSlackStatusSyncTransitionDate(
                for: items,
                rules: rules,
                now: now
            ),
            sharedBoundary
        )
    }
}
