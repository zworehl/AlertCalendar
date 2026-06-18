import AppKit
import Foundation
import XCTest
@testable import AlertCalendar

final class MenuBarRotationStateTests: AlertCalendarModelTestCase {
    func testResolvedMenuBarRotationStateKeepsCurrentSelectionWithinSameSlot() {
        let previousState = CalendarMonitor.MenuBarRotationState(
            slot: 42,
            selectedKey: "match-b",
            selectedIndex: 1
        )

        let resolvedState = CalendarMonitor.resolvedMenuBarRotationState(
            for: ["match-a", "match-b", "match-c"],
            slot: 42,
            previousState: previousState
        )

        XCTAssertEqual(resolvedState.slot, 42)
        XCTAssertEqual(resolvedState.selectedKey, "match-b")
        XCTAssertEqual(resolvedState.selectedIndex, 1)
    }
    func testResolvedMenuBarRotationStateAdvancesWhenSlotChanges() {
        let previousState = CalendarMonitor.MenuBarRotationState(
            slot: 42,
            selectedKey: "match-b",
            selectedIndex: 1
        )

        let resolvedState = CalendarMonitor.resolvedMenuBarRotationState(
            for: ["match-a", "match-b", "match-c"],
            slot: 43,
            previousState: previousState
        )

        XCTAssertEqual(resolvedState.slot, 43)
        XCTAssertEqual(resolvedState.selectedKey, "match-c")
        XCTAssertEqual(resolvedState.selectedIndex, 2)
    }
    func testTimedMenuBarRotationStateKeepsSelectionUntilIntervalExpires() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let previousState = CalendarMonitor.MenuBarRotationState(
            slot: 7,
            selectedKey: "match-b",
            selectedIndex: 1,
            startedAt: start
        )

        let resolvedState = CalendarMonitor.resolvedMenuBarRotationState(
            for: ["match-a", "match-b", "match-c"],
            now: start.addingTimeInterval(9),
            rotationInterval: 10,
            previousState: previousState,
            allowMissingSelectedKeyHold: false
        )

        XCTAssertEqual(resolvedState.slot, 7)
        XCTAssertEqual(resolvedState.selectedKey, "match-b")
        XCTAssertEqual(resolvedState.selectedIndex, 1)
        XCTAssertEqual(resolvedState.startedAt, start)
    }
    func testTimedMenuBarRotationStateAdvancesAfterFullInterval() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let previousState = CalendarMonitor.MenuBarRotationState(
            slot: 7,
            selectedKey: "match-b",
            selectedIndex: 1,
            startedAt: start
        )

        let advanceDate = start.addingTimeInterval(10)
        let resolvedState = CalendarMonitor.resolvedMenuBarRotationState(
            for: ["match-a", "match-b", "match-c"],
            now: advanceDate,
            rotationInterval: 10,
            previousState: previousState,
            allowMissingSelectedKeyHold: false
        )

        XCTAssertEqual(resolvedState.slot, 8)
        XCTAssertEqual(resolvedState.selectedKey, "match-c")
        XCTAssertEqual(resolvedState.selectedIndex, 2)
        XCTAssertEqual(resolvedState.startedAt, advanceDate)
    }
    func testTimedMenuBarRotationStateKeepsReplacementInsideUnifiedQueueWhenItemDisappearsMidInterval() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let previousState = CalendarMonitor.MenuBarRotationState(
            slot: 7,
            selectedKey: "match-b",
            selectedIndex: 1,
            startedAt: start
        )

        let resolvedState = CalendarMonitor.resolvedMenuBarRotationState(
            for: ["match-a", "match-c", "match-d"],
            now: start.addingTimeInterval(5),
            rotationInterval: 10,
            previousState: previousState,
            allowMissingSelectedKeyHold: false
        )

        XCTAssertEqual(resolvedState.slot, 7)
        XCTAssertEqual(resolvedState.selectedKey, "match-c")
        XCTAssertEqual(resolvedState.selectedIndex, 1)
        XCTAssertEqual(resolvedState.startedAt, start)
    }
    func testMenuBarRotationWindowIncludesActiveAndNearFutureItemsButExcludesFarFutureItems() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let activeEvent = UpcomingItem(
            id: "active-event",
            title: "Active",
            date: start.addingTimeInterval(-900),
            endDate: start.addingTimeInterval(900),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: nil,
            calendarName: "Work",
            calendarColor: .systemBlue,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
        let nearFutureEvent = UpcomingItem(
            id: "near-event",
            title: "Near",
            date: start.addingTimeInterval(45 * 60),
            endDate: start.addingTimeInterval(75 * 60),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: nil,
            calendarName: "Work",
            calendarColor: .systemGreen,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
        let farFutureEvent = UpcomingItem(
            id: "far-event",
            title: "Far",
            date: start.addingTimeInterval(3 * 60 * 60),
            endDate: start.addingTimeInterval(4 * 60 * 60),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: nil,
            calendarName: "Work",
            calendarColor: .systemOrange,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )

        XCTAssertTrue(
            CalendarMonitor.shouldIncludeTimedItemInMenuBarRotation(
                activeEvent,
                now: start,
                futureWindowSeconds: 60 * 60
            )
        )
        XCTAssertTrue(
            CalendarMonitor.shouldIncludeTimedItemInMenuBarRotation(
                nearFutureEvent,
                now: start,
                futureWindowSeconds: 60 * 60
            )
        )
        XCTAssertFalse(
            CalendarMonitor.shouldIncludeTimedItemInMenuBarRotation(
                farFutureEvent,
                now: start,
                futureWindowSeconds: 60 * 60
            )
        )
    }
    func testMenuBarRotationWindowIncludesTravelEventWhenLeaveTimeIsNear() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let event = UpcomingItem(
            id: "travel-event",
            title: "Dentist",
            date: now.addingTimeInterval(90 * 60),
            endDate: now.addingTimeInterval(120 * 60),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: 40,
            locationText: "123 Main Street",
            meetingURL: nil,
            calendarID: nil,
            calendarName: "Personal",
            calendarColor: .systemBlue,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
        let virtualMeeting = UpcomingItem(
            id: "virtual-meeting",
            title: "Remote review",
            date: now.addingTimeInterval(90 * 60),
            endDate: now.addingTimeInterval(120 * 60),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: 40,
            locationText: "Google Meet",
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            calendarID: nil,
            calendarName: "Work",
            calendarColor: .systemGreen,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )

        XCTAssertTrue(
            CalendarMonitor.shouldIncludeTimedItemInMenuBarRotation(
                event,
                now: now,
                futureWindowSeconds: 60 * 60
            )
        )
        XCTAssertFalse(
            CalendarMonitor.shouldIncludeTimedItemInMenuBarRotation(
                virtualMeeting,
                now: now,
                futureWindowSeconds: 60 * 60
            )
        )
        XCTAssertEqual(
            CalendarMonitor.menuBarRotationReferenceDate(for: event, now: now),
            now.addingTimeInterval(50 * 60)
        )
    }
    func testPreservedMenuBarSelectionKeyKeepsCurrentSelectionWhenPreferredPoolChangesWithinSameSlot() {
        let previousState = CalendarMonitor.MenuBarRotationState(
            slot: 42,
            selectedKey: "sunset",
            selectedIndex: 1
        )

        let preservedKey = CalendarMonitor.preservedMenuBarSelectionKeyIfNeeded(
            slot: 42,
            previousState: previousState,
            queueKeys: ["event-a", "sunset", "event-b"],
            preferredPoolKeys: ["event-a", "event-b"],
            allowMissingSelectedKeyHold: false
        )

        XCTAssertEqual(preservedKey, "sunset")
    }
    func testPreservedMenuBarSelectionKeyKeepsElapsedPointEventForRestOfSlot() {
        let previousState = CalendarMonitor.MenuBarRotationState(
            slot: 42,
            selectedKey: "sunset",
            selectedIndex: 1
        )

        let preservedKey = CalendarMonitor.preservedMenuBarSelectionKeyIfNeeded(
            slot: 42,
            previousState: previousState,
            queueKeys: ["event-a", "event-b"],
            preferredPoolKeys: ["event-a", "event-b"],
            allowMissingSelectedKeyHold: true
        )

        XCTAssertEqual(preservedKey, "sunset")
    }
    func testPreservedMenuBarSelectionKeyDoesNotKeepSelectionAfterSlotChanges() {
        let previousState = CalendarMonitor.MenuBarRotationState(
            slot: 42,
            selectedKey: "sunset",
            selectedIndex: 1
        )

        let preservedKey = CalendarMonitor.preservedMenuBarSelectionKeyIfNeeded(
            slot: 43,
            previousState: previousState,
            queueKeys: ["event-a", "event-b"],
            preferredPoolKeys: ["event-a", "event-b"],
            allowMissingSelectedKeyHold: true
        )

        XCTAssertNil(preservedKey)
    }
    func testUpdatedFootballGoalHighlightStaysPendingUntilMatchAppears() {
        let highlight = FootballGoalHighlight(matchID: "match-b", scoringSide: .home)

        let updated = CalendarMonitor.updatedFootballGoalHighlight(
            highlight,
            queueMatchIDs: ["match-a", "match-b", "match-c"],
            selectedMatchID: "match-a"
        )

        XCTAssertEqual(updated?.matchID, "match-b")
        XCTAssertEqual(updated?.scoringSide, .home)
        XCTAssertEqual(updated?.hasBeenShownInMenuBar, false)
    }
    func testUpdatedFootballGoalHighlightMarksFirstNaturalAppearance() {
        let highlight = FootballGoalHighlight(matchID: "match-b", scoringSide: .away)

        let updated = CalendarMonitor.updatedFootballGoalHighlight(
            highlight,
            queueMatchIDs: ["match-a", "match-b", "match-c"],
            selectedMatchID: "match-b"
        )

        XCTAssertEqual(updated?.matchID, "match-b")
        XCTAssertEqual(updated?.scoringSide, .away)
        XCTAssertEqual(updated?.hasBeenShownInMenuBar, true)
    }
    func testUpdatedFootballGoalHighlightClearsAfterConsumedAppearance() {
        let highlight = FootballGoalHighlight(
            matchID: "match-b",
            scoringSide: .away,
            hasBeenShownInMenuBar: true
        )

        let updated = CalendarMonitor.updatedFootballGoalHighlight(
            highlight,
            queueMatchIDs: ["match-a", "match-b", "match-c"],
            selectedMatchID: "match-c"
        )

        XCTAssertNil(updated)
    }
    func testShouldHoldElapsedPointInTimeMenuBarItemOnlyForPastInstantEvents() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let pastInstantEvent = UpcomingItem(
            id: "sunset",
            title: "Sunset",
            date: now.addingTimeInterval(-5),
            endDate: nil,
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: nil,
            calendarName: "Astronomy",
            calendarColor: .systemOrange,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
        let activeTimedEvent = UpcomingItem(
            id: "meeting",
            title: "Meeting",
            date: now.addingTimeInterval(-300),
            endDate: now.addingTimeInterval(300),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: "cal-1",
            calendarName: "Work",
            calendarColor: .systemBlue,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
        let futureInstantEvent = UpcomingItem(
            id: "sunrise",
            title: "Sunrise",
            date: now.addingTimeInterval(120),
            endDate: nil,
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: nil,
            calendarName: "Astronomy",
            calendarColor: .systemYellow,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )

        XCTAssertTrue(CalendarMonitor.shouldHoldElapsedPointInTimeMenuBarItem(pastInstantEvent, now: now))
        XCTAssertFalse(CalendarMonitor.shouldHoldElapsedPointInTimeMenuBarItem(activeTimedEvent, now: now))
        XCTAssertFalse(CalendarMonitor.shouldHoldElapsedPointInTimeMenuBarItem(futureInstantEvent, now: now))
    }}
