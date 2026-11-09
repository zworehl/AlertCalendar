import AppKit
import XCTest
@testable import AlertCalendar

final class PinnedFootballMenuBarScoreTests: AlertCalendarModelTestCase {
    @MainActor
    func testMenuBarCombinesEventAndProvidedScoreBadges() {
        let event = NSImage(size: CGSize(width: 100, height: 20))
        let first = NSImage(size: CGSize(width: 70, height: 18))
        let second = NSImage(size: CGSize(width: 80, height: 22))
        let combined = MenuBarStatusLabel.combinedBadgeImage(event: event, scores: [first, second])
        XCTAssertEqual(combined.size, CGSize(width: 262, height: 22))
        XCTAssertTrue(MenuBarStatusLabel.combinedBadgeImage(event: event, scores: []) === event)
    }

    func testOnlyLiveMatchesLeaveRotationWhenPinningIsEnabled() {
        var settings = AppSettings.defaults
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let live = makeFootballUpcomingItem(makeFootballMatch(
            id: "live", startDate: now, actualStartDate: nil,
            statusState: .inProgress, statusText: "3'"
        ))
        let scheduled = makeFootballUpcomingItem(makeFootballMatch(
            id: "scheduled", startDate: now, actualStartDate: nil,
            statusState: .scheduled, statusText: "Scheduled"
        ))
        let finished = makeFootballUpcomingItem(makeFootballMatch(
            id: "finished", startDate: now, actualStartDate: nil,
            statusState: .finished, statusText: "FT"
        ))
        settings.pinLiveFootballScoresInMenuBar = true
        XCTAssertTrue(CalendarMonitor.shouldPinLiveFootballItem(live, settings: settings))
        XCTAssertFalse(CalendarMonitor.shouldPinLiveFootballItem(scheduled, settings: settings))
        XCTAssertFalse(CalendarMonitor.shouldPinLiveFootballItem(finished, settings: settings))
        settings.pinLiveFootballScoresInMenuBar = false
        XCTAssertFalse(CalendarMonitor.shouldPinLiveFootballItem(live, settings: settings))
    }

    func testPinningPreferenceSurvivesDraftAndPersistence() throws {
        let suite = "PinnedFootball.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSettingsStore(defaults: defaults)
        store.registerDefaults()
        XCTAssertTrue(store.load().pinLiveFootballScoresInMenuBar)
        var draft = SettingsDraft(settings: store.load())
        draft.pinLiveFootballScoresInMenuBar = false
        let settings = draft.applied(to: store.load(), availableEventCalendarIDs: [])
        store.save(settings)
        XCTAssertFalse(store.load().pinLiveFootballScoresInMenuBar)
    }

    func testLiveScoresRotateOnTheirOwnScheduleBesideEvents() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let scores = [makePinnedScore(id: "first"), makePinnedScore(id: "second")]
        var eventState = CalendarMonitor.resolvedMenuBarRotationState(
            for: ["meeting", "reminder"], now: now, rotationInterval: 30,
            previousState: .init(), allowMissingSelectedKeyHold: false
        )
        var scoreState = CalendarMonitor.MenuBarRotationState()
        XCTAssertEqual(select(scores, at: now.addingTimeInterval(10), state: &scoreState)?.id, "first")

        eventState = CalendarMonitor.resolvedMenuBarRotationState(
            for: ["meeting", "reminder"], now: now.addingTimeInterval(30), rotationInterval: 30,
            previousState: eventState, allowMissingSelectedKeyHold: false
        )
        XCTAssertEqual(eventState.selectedKey, "reminder")
        XCTAssertEqual(select(scores, at: now.addingTimeInterval(30), state: &scoreState)?.id, "first")
        XCTAssertEqual(select(scores, at: now.addingTimeInterval(40), state: &scoreState)?.id, "second")
        XCTAssertEqual(eventState.selectedKey, "reminder")
        XCTAssertEqual(eventState.startedAt, now.addingTimeInterval(30))
        XCTAssertEqual(select(scores, at: now.addingTimeInterval(70), state: &scoreState)?.id, "first")
    }

    func testScoreRefreshAndNewMatchKeepCurrentTurnAndShowUpdatedScore() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = makePinnedScore(id: "first")
        let second = makePinnedScore(id: "second")
        var state = CalendarMonitor.MenuBarRotationState()
        XCTAssertEqual(select([first, second], at: now, state: &state)?.display.homeScore, "0")

        let updatedFirst = makePinnedScore(id: "first", homeScore: "2")
        let third = makePinnedScore(id: "third")
        let updatedScores = [updatedFirst, second, third]
        let displayed = select(updatedScores, at: now.addingTimeInterval(20), state: &state)
        XCTAssertEqual(displayed?.id, "first")
        XCTAssertEqual(displayed?.display.homeScore, "2")
        XCTAssertEqual(state.startedAt, now)
        XCTAssertEqual(select(updatedScores, at: now.addingTimeInterval(30), state: &state)?.id, "second")
        XCTAssertEqual(select(updatedScores, at: now.addingTimeInterval(60), state: &state)?.id, "third")
        XCTAssertEqual(select(updatedScores, at: now.addingTimeInterval(90), state: &state)?.id, "first")
    }

    func testFinishedMatchDisappearsImmediatelyAndEmptyScoresResetRotation() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = makePinnedScore(id: "first")
        let second = makePinnedScore(id: "second")
        var state = CalendarMonitor.MenuBarRotationState()
        XCTAssertEqual(select([first, second], at: now, state: &state)?.id, "first")
        XCTAssertEqual(select([second], at: now.addingTimeInterval(5), state: &state)?.id, "second")
        XCTAssertNil(select([], at: now.addingTimeInterval(10), state: &state))
        XCTAssertEqual(state, .init())
        XCTAssertEqual(select([first, second], at: now.addingTimeInterval(11), state: &state)?.id, "first")
        XCTAssertEqual(state.startedAt, now.addingTimeInterval(11))
    }

    func testHiddenMatchGoalWaitsForItsScoreRotationTurn() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let scores = [makePinnedScore(id: "first"), makePinnedScore(id: "second", homeScore: "1")]
        var state = CalendarMonitor.MenuBarRotationState()
        let first = select(scores, at: now, state: &state)
        let pending = CalendarMonitor.updatedFootballGoalHighlight(
            FootballGoalHighlight(matchID: "second", scoringSide: .home),
            queueMatchIDs: Set(scores.map(\.id)), selectedMatchID: first?.id,
            now: now, rotationInterval: 30
        )
        XCTAssertNotNil(pending)
        XCTAssertNil(pending?.firstShownInMenuBarAt)

        let second = select(scores, at: now.addingTimeInterval(30), state: &state)
        let shown = CalendarMonitor.updatedFootballGoalHighlight(
            pending, queueMatchIDs: Set(scores.map(\.id)), selectedMatchID: second?.id,
            now: now.addingTimeInterval(30), rotationInterval: 30
        )
        XCTAssertEqual(shown?.firstShownInMenuBarAt, now.addingTimeInterval(30))
        XCTAssertNil(CalendarMonitor.updatedFootballGoalHighlight(
            shown, queueMatchIDs: Set(scores.map(\.id)),
            selectedMatchID: select(scores, at: now.addingTimeInterval(60), state: &state)?.id,
            now: now.addingTimeInterval(60), rotationInterval: 30
        ))
    }

    private func select(
        _ scores: [PinnedFootballMenuBarScore],
        at now: Date,
        state: inout CalendarMonitor.MenuBarRotationState
    ) -> PinnedFootballMenuBarScore? {
        CalendarMonitor.rotatingPinnedFootballMenuBarScore(
            from: scores, now: now, rotationInterval: 30, rotationState: &state
        )
    }

    private func makePinnedScore(id: String, homeScore: String = "0") -> PinnedFootballMenuBarScore {
        let match = makeFootballMatch(
            id: id, startDate: Date(timeIntervalSince1970: 1_800_000_000), actualStartDate: nil,
            statusState: .inProgress, statusText: "3'", homeScore: homeScore
        )
        return PinnedFootballMenuBarScore(
            id: id, calendarColor: .systemBlue, backgroundProgress: 0.5,
            display: FootballFixtureFormatter.menuBarDisplay(
                for: match, competitionLocalLogoURL: nil, homeLocalLogoURL: nil, awayLocalLogoURL: nil
            ),
            statusText: "3'", highlightSide: nil, highlightOpacity: 0
        )
    }
}
