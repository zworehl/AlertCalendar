import Foundation
import XCTest
@testable import AlertCalendar

final class SettingsEsportsPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAddedMatchesKeepTrackedPostponedAndOutOfWindowMatches() {
        var old = match(1, date: now.addingTimeInterval(-300 * 86_400))
        old.status = .postponed
        let distant = match(2, date: now.addingTimeInterval(300 * 86_400))
        let pending = [distant.id: SettingsPendingItemChange(item: distant, mutation: .add)]
        let shown = visible([old], mode: .added, managed: [old.id], pending: pending)
        XCTAssertEqual(Set(shown.map(\.id)), [old.id, distant.id])
        XCTAssertNil(SettingsEsportsPresentation.startDate(for: old), "A postponed old schedule is not a confirmed time")
    }

    func testScheduleKeepsTBDTimeWhileNowViewDoesNotInventAStart() {
        let unknown = match(1, date: nil)
        XCTAssertEqual(visible([unknown], mode: .schedule).map(\.id), [unknown.id])
        XCTAssertTrue(visible([unknown], mode: .nowAndNextDay).isEmpty)
        XCTAssertNil(SettingsEsportsPresentation.startDate(for: unknown))
    }

    func testNowViewUsesReportedRunningStatusAndExact24HourWindow() {
        var running = match(1, date: nil)
        running.status = .running
        let edge = match(2, date: now.addingTimeInterval(86_400))
        let outside = match(3, date: now.addingTimeInterval(86_401))
        let previous = match(4, date: now.addingTimeInterval(-1))
        XCTAssertEqual(Set(visible([running, edge, outside, previous], mode: .nowAndNextDay).map(\.id)), [running.id, edge.id])
    }

    func testGameAndNamespacedCompetitionFiltersDoNotMixEqualProviderIDs() {
        var lol = match(1, date: now)
        lol.competitionID = 7; lol.competitionName = "World Championship"
        var cs = match(2, date: now, game: .counterStrike2)
        cs.competitionID = 7; cs.competitionName = "World Championship"
        let options = SettingsEsportsPresentation.competitions(in: [lol, cs], game: nil)
        XCTAssertEqual(Set(options.map(\.id)), ["leagueOfLegends:7", "counterStrike2:7"])
        let shown = SettingsEsportsPresentation.visibleMatches(
            [lol, cs], game: nil, competitionKey: "counterStrike2:7", mode: .schedule,
            preferences: .defaults, now: now, managedIDs: [], pending: [:]
        )
        XCTAssertEqual(shown.map(\.id), [cs.id])
    }

    func testScoresRequireParticipantIdentityAndAReportedResultStatus() {
        let team = EsportsOpponent(id: 1, name: "Team", type: .team)
        let player = EsportsOpponent(id: 1, name: "Player", type: .player)
        var fixture = match(1, date: now)
        fixture.opponents = [team, player]
        fixture.results = [EsportsScore(opponentID: 1, opponentType: .player, score: 2)]
        XCTAssertNil(SettingsEsportsPresentation.displayedScore(for: player, in: fixture), "Scheduled zeroes/results must not appear as live scores")
        fixture.status = .finished
        XCTAssertEqual(SettingsEsportsPresentation.displayedScore(for: player, in: fixture), 2)
        XCTAssertNil(SettingsEsportsPresentation.displayedScore(for: team, in: fixture), "Missing results never become zero")
    }

    func testStagingIsReversibleAndNeverAdoptsExternalCalendarEvents() {
        let fixture = match(1, date: now)
        let added = SettingsEsportsPresentation.toggledPendingChanges(for: fixture, presence: .absent, changes: [:])
        XCTAssertEqual(added[fixture.id]?.mutation, .add)
        XCTAssertTrue(SettingsEsportsPresentation.toggledPendingChanges(for: fixture, presence: .absent, changes: added).isEmpty)
        XCTAssertTrue(SettingsEsportsPresentation.toggledPendingChanges(for: fixture, presence: .external, changes: [:]).isEmpty)
        XCTAssertTrue(SettingsEsportsPresentation.toggledPendingChanges(for: fixture, presence: .external, changes: added).isEmpty,
                      "An external event discovered during staging can only undo the pending request")
        let removed = SettingsEsportsPresentation.toggledPendingChanges(for: fixture, presence: .managed, changes: [:])
        XCTAssertEqual(removed[fixture.id]?.mutation, .remove)
        XCTAssertTrue(visible([fixture], mode: .added, managed: [fixture.id], pending: removed).isEmpty)
    }

    func testSupportedCalendarCompetitionRemainsVisibleWithoutGamingNews() {
        let competition = local("competition", game: .starCraft2, kind: .competitive)
        let release = local("release", game: .starCraft2, kind: .gamingEvent)
        let other = local("other", game: .counterStrike2, kind: .competitive)
        let shown = SettingsEsportsPresentation.visibleLocalEvents(
            [competition, release, other], game: .starCraft2, mode: .schedule,
            preferences: .defaults, now: now
        )
        XCTAssertEqual(shown.map(\.id), [competition.id])
    }

    func testLegacyUnsupportedGamesCannotReappearThroughCachedCardsOrPendingChanges() {
        let unsupported = [EsportsGame.ageOfEmpires2, .geoGuessr, .granTurismo7]
        let matches = unsupported.enumerated().map { index, game in match(index + 1, date: now, game: game) }
        let events = unsupported.map { local($0.rawValue, game: $0, kind: .competitive) }
        let pending = Dictionary(uniqueKeysWithValues: matches.map { ($0.id, SettingsPendingItemChange(item: $0, mutation: .add)) })
        for mode in SettingsEsportsBrowseMode.allCases {
            XCTAssertTrue(visible(matches, mode: mode, managed: Set(matches.map(\.id)), pending: pending).isEmpty)
            XCTAssertTrue(SettingsEsportsPresentation.visibleLocalEvents(
                events, game: nil, mode: mode, preferences: .defaults, now: now
            ).isEmpty)
        }
        XCTAssertTrue(SettingsEsportsPresentation.competitions(in: matches, game: nil).isEmpty)
    }

    func testPendingChangesRemainUndoableAfterCalendarAccessOrDestinationDisappears() {
        let fixture = match(1, date: now)
        for (presence, mutation) in [(EsportsMatchPresence.absent, SettingsPendingMutation.add), (.managed, .remove)] {
            let pending = SettingsPendingItemChange(item: fixture, mutation: mutation)
            XCTAssertTrue(SettingsEsportsPresentation.canTogglePendingChange(
                presence: presence, pending: pending, canAdd: false, canRemove: false
            ))
            XCTAssertTrue(SettingsEsportsPresentation.toggledPendingChanges(
                for: fixture, presence: presence, changes: [fixture.id: pending]
            ).isEmpty)
        }
        XCTAssertFalse(SettingsEsportsPresentation.canTogglePendingChange(
            presence: .absent, pending: nil, canAdd: false, canRemove: false
        ), "Losing access still prevents a new write request")
    }

    private func visible(
        _ matches: [EsportsMatch], mode: SettingsEsportsBrowseMode,
        managed: Set<String> = [], pending: [String: SettingsPendingItemChange<EsportsMatch>] = [:]
    ) -> [EsportsMatch] {
        SettingsEsportsPresentation.visibleMatches(matches, game: nil, competitionKey: nil, mode: mode,
            preferences: .defaults, now: now, managedIDs: managed, pending: pending)
    }

    private func match(_ id: Int, date: Date?, game: EsportsGame = .leagueOfLegends) -> EsportsMatch {
        var fixture = EsportsMatch(providerID: id, game: game, name: "Match \(id)")
        fixture.status = .scheduled; fixture.scheduledAt = date
        return fixture
    }

    private func local(_ id: String, game: EsportsGame, kind: LocalGamingCalendarEvent.Kind) -> LocalGamingCalendarEvent {
        LocalGamingCalendarEvent(id: id, game: game, title: id, startDate: now, endDate: now.addingTimeInterval(3_600),
            isAllDay: false, calendarID: "calendar", calendarName: "Gaming", sourceURL: nil,
            eventIdentifier: id, eventUID: nil, kind: kind, providerMatchID: nil)
    }
}
