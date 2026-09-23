import XCTest
@testable import AlertCalendar

final class FocusCalendarFilterStateTests: XCTestCase {
    func testFocusOffRestoresTheUsualSelection() {
        XCTAssertEqual(visible(nil), ["work", "personal"])
    }

    func testHideSelectedOnlyRemovesThoseCalendars() {
        XCTAssertEqual(visible(.init(action: .hideSelected, calendarIDs: ["work"])), ["personal"])
    }

    func testShowOnlyCanSelectACalendarOutsideTheUsualSelection() {
        XCTAssertEqual(visible(.init(action: .showOnlySelected, calendarIDs: ["sports"])), ["sports"])
    }

    func testDeletingEveryCalendarInAShowOnlyFilterDoesNotRevealOtherCalendars() {
        XCTAssertEqual(visible(.init(action: .showOnlySelected, calendarIDs: ["deleted"])), [])
        XCTAssertEqual(visible(.init(action: .showOnlySelected, calendarIDs: [])), [])
    }

    func testReminderAndEventSelectionsAreIndependent() {
        let state = FocusCalendarFilterState(
            eventSelection: .init(action: .hideSelected, calendarIDs: ["work"]),
            reminderSelection: .init(action: .showOnlySelected, calendarIDs: ["sports"])
        )
        XCTAssertEqual(visible(state.selection(for: .event)), ["personal"])
        XCTAssertEqual(visible(state.selection(for: .reminder)), ["sports"])
    }

    func testNativeIntentDefaultsClearTheFilterAndExplicitShowNoneRemainsActive() {
        let defaultFilter = AlertCalendarFocusFilter()
        XCTAssertNil(AlertCalendarFocusFilter.state(from: defaultFilter))

        var filter = AlertCalendarFocusFilter()
        filter.eventCalendarRule = .showOnlySelected
        filter.eventCalendars = []
        let state = AlertCalendarFocusFilter.state(from: filter)
        XCTAssertTrue(state?.hasActiveOverrides == true)
        XCTAssertEqual(visible(state?.selection(for: .event)), [])
        XCTAssertNil(state?.selection(for: .reminder))
    }

    func testFocusPersistenceSurvivesSettingsRegistrationAndNeverOverwritesBaseSelection() throws {
        let suiteName = "FocusFilterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["work", "personal"], forKey: DefaultsKeys.selectedEventCalendarIDs)
        let state = FocusCalendarFilterState(
            eventSelection: .init(action: .showOnlySelected, calendarIDs: ["sports"])
        )
        FocusCalendarFilterStateStore.save(state, defaults: defaults)
        AppSettingsStore(defaults: defaults).registerDefaults()
        XCTAssertEqual(FocusCalendarFilterStateStore.load(defaults: defaults), state)
        XCTAssertEqual(AppSettingsStore(defaults: defaults).selectedCalendarIDs(for: .event), ["work", "personal"])

        FocusCalendarFilterStateStore.save(nil, defaults: defaults)
        XCTAssertNil(FocusCalendarFilterStateStore.load(defaults: defaults))
        XCTAssertEqual(AppSettingsStore(defaults: defaults).selectedCalendarIDs(for: .event), ["work", "personal"])
    }

    func testFocusRefreshReadsCalendarsWithoutWritingManagedFeeds() {
        let plan = CalendarMonitorRefreshPlan(reasons: [.focusFilterChanged])
        XCTAssertTrue(plan.refreshesCalendarStateOnly)
        XCTAssertTrue(plan.schedulesReminderFetch)
        XCTAssertFalse(plan.triggersManagedFootballSync)
        XCTAssertFalse(plan.triggersFootballAutoAddSync)
    }

    private func visible(_ selection: FocusCalendarSelectionOverride?) -> Set<String> {
        FocusCalendarFilterStateStore.effectiveSelectedCalendarIDs(
            baseSelectedIDs: ["work", "personal"], availableIDs: ["work", "personal", "sports"],
            focusOverride: selection
        )
    }
}
