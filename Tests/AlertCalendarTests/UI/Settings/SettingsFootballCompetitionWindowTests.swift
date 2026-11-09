import Foundation
import XCTest
@testable import AlertCalendar

final class SettingsFootballCompetitionWindowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_720_000_000)

    func testCompetitionVisibilityUsesTheSameExactWindowAsCards() {
        let edge = now.addingTimeInterval(14 * 86_400)
        let visible = FootballTestData.match(id: "edge", startDate: edge, statusState: .scheduled)
        let hidden = FootballTestData.match(id: "beyond", startDate: edge.addingTimeInterval(1), statusState: .scheduled)
        let sections = [section(.premierLeague, matches: [visible]), section(.worldCup, matches: [hidden])]

        let groups = SettingsFootballFixturesSectionView.browsableCompetitionSectionsByRegion(
            from: sections, now: now, lookbackDays: 7, lookaheadDays: 14
        )
        XCTAssertEqual(groups.flatMap(\.sections).map(\.id), [FootballCompetitionPreset.premierLeague.id])
        XCTAssertEqual(SettingsFootballFixturesSectionView.displayedMatches(
            [visible, hidden], now: now, lookbackDays: 7, lookaheadDays: 14, showFinishedMatches: true
        ).map(\.id), ["edge"])
    }

    func testIncreasingWindowRevealsCompetitionWithoutOpeningIt() {
        let match = FootballTestData.match(id: "later", startDate: now.addingTimeInterval(20 * 86_400), statusState: .scheduled)
        let sections = [section(.worldCup, matches: [match])]
        XCTAssertTrue(SettingsFootballFixturesSectionView.browsableCompetitionSectionsByRegion(
            from: sections, now: now, lookbackDays: 7, lookaheadDays: 14
        ).isEmpty)
        XCTAssertEqual(SettingsFootballFixturesSectionView.browsableCompetitionSectionsByRegion(
            from: sections, now: now, lookbackDays: 7, lookaheadDays: 30
        ).flatMap(\.sections).count, 1)
    }

    func testDiscoveryIncludesKickoffBeforeTheDateBoundaryWhenFinishedEndIsInsideLookback() {
        let calendar = Calendar.autoupdatingCurrent
        let midnight = calendar.startOfDay(for: now)
        let reference = midnight.addingTimeInterval(15 * 60)
        let cutoff = calendar.date(byAdding: .day, value: -7, to: reference)!
        let kickoff = cutoff.addingTimeInterval(-45 * 60)
        let match = FootballTestData.match(id: "overnight", startDate: kickoff, statusState: .finished)
        let query = FootballCompetitionAvailabilityWindow(now: reference, lookbackDays: 7, lookaheadDays: 14)
        XCTAssertLessThanOrEqual(query.start, kickoff)
        XCTAssertEqual(SettingsFootballFixturesSectionView.displayedMatches(
            [match], now: reference, lookbackDays: 7, lookaheadDays: 14, showFinishedMatches: true
        ).map(\.id), ["overnight"])
    }

    func testFinishedOnlyCompetitionFollowsFinishedFilterAndLookback() {
        let match = FootballTestData.match(id: "finished", startDate: now.addingTimeInterval(-2 * 86_400), statusState: .finished)
        let sections = [section(.premierLeague, matches: [match])]
        XCTAssertEqual(SettingsFootballFixturesSectionView.browsableCompetitionSectionsByRegion(
            from: sections, now: now, lookbackDays: 7, lookaheadDays: 14, showFinishedMatches: true
        ).flatMap(\.sections).count, 1)
        XCTAssertTrue(SettingsFootballFixturesSectionView.browsableCompetitionSectionsByRegion(
            from: sections, now: now, lookbackDays: 7, lookaheadDays: 14, showFinishedMatches: false
        ).isEmpty)
        XCTAssertTrue(SettingsFootballFixturesSectionView.browsableCompetitionSectionsByRegion(
            from: sections, now: now, lookbackDays: 1, lookaheadDays: 14, showFinishedMatches: true
        ).isEmpty)
    }

    func testUnknownParticipantsDoNotKeepAnOtherwiseEmptyCompetitionVisible() {
        let unknown = FootballTeamSummary(
            id: "gro", name: "GRO", abbreviation: "GRO", logoURL: nil, countryName: "Group A Winner", isNational: true
        )
        let match = FootballTestData.match(id: "unresolved", startDate: now, statusState: .scheduled, homeTeam: unknown)
        XCTAssertTrue(SettingsFootballFixturesSectionView.browsableCompetitionSectionsByRegion(
            from: [section(.worldCup, matches: [match])], now: now
        ).isEmpty)
    }

    func testLiveMatchAndFailedCompetitionRemainAvailable() {
        let live = FootballTestData.match(id: "live", startDate: now.addingTimeInterval(-2 * 86_400), statusState: .inProgress)
        let failed = FootballMenuCompetitionSection(
            competition: .worldCup, matches: [], errorMessage: "Offline", isLoading: false, hasLoaded: false
        )
        let groups = SettingsFootballFixturesSectionView.browsableCompetitionSectionsByRegion(
            from: [section(.premierLeague, matches: [live]), failed], now: now,
            lookbackDays: 1, lookaheadDays: 1, showFinishedMatches: false
        )
        XCTAssertEqual(Set(groups.flatMap(\.sections).map(\.id)), Set([FootballCompetitionPreset.premierLeague.id, failed.id]))
    }

    private func section(_ competition: FootballCompetitionPreset, matches: [FootballFixtureMatch]) -> FootballMenuCompetitionSection {
        FootballMenuCompetitionSection(competition: competition, matches: matches, errorMessage: nil, isLoading: false, hasLoaded: true)
    }
}
