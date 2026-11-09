import XCTest
@testable import AlertCalendar

final class SettingsFootballFixturesFeedbackTests: XCTestCase {
    func testCompetitionLayoutUsesStableTwoColumnMetrics() {
        XCTAssertEqual(SettingsFootballFixturesSectionView.competitionSidebarWidth, 320)
        XCTAssertEqual(SettingsFootballFixturesSectionView.competitionColumnSpacing, 16)
        XCTAssertEqual(SettingsFootballFixturesSectionView.competitionSelectionStatusWidth, 72)
        XCTAssertEqual(SettingsFootballFixturesSectionView.competitionSelectionStatusHeight, 18)
        XCTAssertEqual(SettingsFootballFixturesSectionView.minimumMatchListViewportHeight, 120)
        XCTAssertEqual(SettingsFootballFixturesSectionView.maximumMatchListViewportHeight, 1_200)
    }

    func testCompetitionSelectionSurvivesRefreshReorderingAndRepeatedRegionSelection() {
        let first = makeSection(competition: .premierLeague, matches: [], errorMessage: nil, isLoading: false, hasLoaded: true)
        let selected = makeSection(competition: .worldCup, matches: [], errorMessage: nil, isLoading: false, hasLoaded: true)
        XCTAssertEqual(SettingsFootballFixturesSectionView.preferredCompetitionID(in: [first, selected], currentID: selected.id), selected.id)
        XCTAssertEqual(SettingsFootballFixturesSectionView.preferredCompetitionID(in: [selected, first], currentID: selected.id), selected.id)
        XCTAssertEqual(SettingsFootballFixturesSectionView.preferredCompetitionID(in: [first], currentID: selected.id), first.id)
        XCTAssertNil(SettingsFootballFixturesSectionView.preferredCompetitionID(in: [], currentID: selected.id))
    }

    func testCompetitionOffseasonFeedbackAppliesToLoadedEmptySuccessfulSection() {
        let section = makeSection(matches: [], errorMessage: nil, isLoading: false, hasLoaded: true)

        XCTAssertTrue(SettingsFootballFixturesSectionView.isCompetitionOffseason(section))
        XCTAssertEqual(SettingsFootballFixturesSectionView.competitionOffseasonFeedbackTitle, "Offseason")
        XCTAssertEqual(
            SettingsFootballFixturesSectionView.competitionOffseasonFeedbackText(for: .majorLeagueSoccer),
            "No fixtures are available for MLS in the last 90 days and next 90 days. This competition appears to be in its offseason."
        )
    }

    func testCompetitionOffseasonFeedbackIgnoresNonOffseasonStates() {
        let scheduledMatch = FootballTestData.match(
            id: "mls-scheduled",
            competitionSlug: FootballCompetitionPreset.majorLeagueSoccer.slug,
            competitionName: FootballCompetitionPreset.majorLeagueSoccer.title,
            statusState: .scheduled
        )

        XCTAssertFalse(SettingsFootballFixturesSectionView.isCompetitionOffseason(
            makeSection(matches: [], errorMessage: nil, isLoading: false, hasLoaded: false)
        ))
        XCTAssertFalse(SettingsFootballFixturesSectionView.isCompetitionOffseason(
            makeSection(matches: [], errorMessage: nil, isLoading: true, hasLoaded: false)
        ))
        XCTAssertFalse(SettingsFootballFixturesSectionView.isCompetitionOffseason(
            makeSection(matches: [], errorMessage: "Could not load fixtures right now.", isLoading: false, hasLoaded: true)
        ))
        XCTAssertFalse(SettingsFootballFixturesSectionView.isCompetitionOffseason(
            makeSection(matches: [scheduledMatch], errorMessage: nil, isLoading: false, hasLoaded: true)
        ))
    }

    func testBrowseListHidesOffseasonCompetitionsAndEmptyRegions() {
        let offseason = makeSection(competition: .worldCup, matches: [], errorMessage: nil, isLoading: false, hasLoaded: true)
        let active = makeSection(
            competition: .premierLeague, matches: [FootballTestData.match(id: "fixture", statusState: .scheduled)],
            errorMessage: nil, isLoading: false, hasLoaded: true
        )
        let groups = SettingsFootballFixturesSectionView.browsableCompetitionSectionsByRegion(from: [offseason, active], now: Date(timeIntervalSince1970: 1_720_000_000))
        XCTAssertEqual(groups.map(\.region), [.europe])
        XCTAssertEqual(groups.flatMap(\.sections).map(\.id), [active.id])
    }

    func testBrowseListWaitsForUnknownCompetitionsAndKeepsFailuresRetryable() {
        let unloaded = makeSection(competition: .majorLeagueSoccer, matches: [], errorMessage: nil, isLoading: false, hasLoaded: false)
        let loading = makeSection(competition: .goldCup, matches: [], errorMessage: nil, isLoading: true, hasLoaded: false)
        let failed = makeSection(competition: .worldCup, matches: [], errorMessage: "Offline", isLoading: false, hasLoaded: true)
        let groups = SettingsFootballFixturesSectionView.browsableCompetitionSectionsByRegion(from: [unloaded, loading, failed], now: Date(timeIntervalSince1970: 1_720_000_000))
        XCTAssertEqual(groups.flatMap(\.sections).map(\.id), [failed.id])
    }

    func testOffseasonCompetitionStaysHiddenWhileRefreshingAndReturnsWithFixtures() {
        let refreshing = makeSection(matches: [], errorMessage: nil, isLoading: true, hasLoaded: true)
        XCTAssertTrue(SettingsFootballFixturesSectionView.browsableCompetitionSectionsByRegion(from: [refreshing], now: Date(timeIntervalSince1970: 1_720_000_000)).isEmpty)

        let refreshed = makeSection(
            matches: [FootballTestData.match(id: "new-fixture", statusState: .scheduled)], errorMessage: nil,
            isLoading: false, hasLoaded: true
        )
        let groups = SettingsFootballFixturesSectionView.browsableCompetitionSectionsByRegion(from: [refreshed], now: Date(timeIntervalSince1970: 1_720_000_000))
        XCTAssertEqual(groups.flatMap(\.sections).map(\.id), [refreshed.id])
    }

    func testFootballCardsExcludeMatchesWithAnyPendingParticipant() {
        let knownMatch = FootballTestData.match(
            id: "known",
            statusState: .scheduled
        )
        let unknownHomeMatch = FootballTestData.match(
            id: "unknown-home",
            statusState: .scheduled,
            homeTeam: FootballTeamSummary(
                id: "gro",
                name: "GRO",
                abbreviation: "GRO",
                logoURL: nil,
                countryName: "Group A Winner",
                isNational: true
            )
        )
        let unknownAwayMatch = FootballTestData.match(
            id: "unknown-away",
            statusState: .inProgress,
            awayTeam: FootballTeamSummary(
                id: "sfl",
                name: "SFL",
                abbreviation: "SFL",
                logoURL: nil,
                countryName: "Semifinal 1 Loser",
                isNational: true
            )
        )

        XCTAssertEqual(
            SettingsFootballFixturesSectionView.matchesEligibleForFootballCards([
                unknownHomeMatch,
                knownMatch,
                unknownAwayMatch,
            ]).map(\.id),
            ["known"]
        )
    }

    private func makeSection(
        competition: FootballCompetitionPreset = .majorLeagueSoccer,
        matches: [FootballFixtureMatch],
        errorMessage: String?,
        isLoading: Bool,
        hasLoaded: Bool
    ) -> FootballMenuCompetitionSection {
        FootballMenuCompetitionSection(
            competition: competition,
            matches: matches,
            errorMessage: errorMessage,
            isLoading: isLoading,
            hasLoaded: hasLoaded
        )
    }
}
