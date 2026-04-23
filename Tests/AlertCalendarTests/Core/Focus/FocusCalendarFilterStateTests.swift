import XCTest
@testable import AlertCalendar

final class FocusCalendarFilterStateTests: XCTestCase {
    func testEffectiveSelectedCalendarIDsKeepsBaseSelectionWhenNoFocusOverrideExists() {
        let result = FocusCalendarFilterStateStore.effectiveSelectedCalendarIDs(
            baseSelectedIDs: ["work", "personal", "stale"],
            availableIDs: ["work", "personal", "family"],
            focusOverride: nil
        )

        XCTAssertEqual(result, ["work", "personal"])
    }

    func testEffectiveSelectedCalendarIDsRemovesHiddenCalendarsFromBaseSelection() {
        let result = FocusCalendarFilterStateStore.effectiveSelectedCalendarIDs(
            baseSelectedIDs: ["work", "personal", "family"],
            availableIDs: ["work", "personal", "family"],
            focusOverride: FocusCalendarSelectionOverride(
                action: .hideSelected,
                calendarIDs: ["work", "family"]
            )
        )

        XCTAssertEqual(result, ["personal"])
    }

    func testEffectiveSelectedCalendarIDsShowsOnlyCalendarsSelectedInFocusOverride() {
        let result = FocusCalendarFilterStateStore.effectiveSelectedCalendarIDs(
            baseSelectedIDs: ["work", "personal", "family"],
            availableIDs: ["work", "personal", "family", "shared"],
            focusOverride: FocusCalendarSelectionOverride(
                action: .showOnlySelected,
                calendarIDs: ["family", "shared"]
            )
        )

        XCTAssertEqual(result, ["family", "shared"])
    }

    func testNormalizedStateDropsUnavailableCalendarsAndReturnsNilWhenNothingRemains() {
        let state = FocusCalendarFilterState(
            eventSelection: FocusCalendarSelectionOverride(
                action: .hideSelected,
                calendarIDs: ["work"]
            ),
            reminderSelection: FocusCalendarSelectionOverride(
                action: .showOnlySelected,
                calendarIDs: ["reminders"]
            )
        )

        XCTAssertNil(
            state.normalized(
                availableEventIDs: ["personal"],
                availableReminderIDs: ["inbox"]
            )
        )
    }
}
