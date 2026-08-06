import XCTest
@testable import AlertCalendar

final class SettingsFootballFixturesFeedbackTests: XCTestCase {
    func testCompetitionLayoutReservesAStableFullHeightSidebarBelowTheControls() {
        XCTAssertEqual(SettingsFootballFixturesSectionView.competitionSidebarWidth, 320)
        XCTAssertEqual(SettingsFootballFixturesSectionView.competitionColumnSpacing, 16)
    }

    func testCompetitionOffseasonFeedbackAppliesToLoadedEmptySuccessfulSection() {
        let section = makeSection(matches: [], errorMessage: nil, isLoading: false, hasLoaded: true)

        XCTAssertTrue(SettingsFootballFixturesSectionView.isCompetitionOffseason(section))
        XCTAssertEqual(SettingsFootballFixturesSectionView.competitionOffseasonFeedbackTitle, "Offseason")
        XCTAssertEqual(
            SettingsFootballFixturesSectionView.competitionOffseasonFeedbackText(for: .majorLeagueSoccer),
            "No fixtures are available for MLS in the last 45 days and next 90 days. This competition appears to be in its offseason."
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
            makeSection(matches: [], errorMessage: nil, isLoading: true, hasLoaded: true)
        ))
        XCTAssertFalse(SettingsFootballFixturesSectionView.isCompetitionOffseason(
            makeSection(matches: [], errorMessage: "Could not load fixtures right now.", isLoading: false, hasLoaded: true)
        ))
        XCTAssertFalse(SettingsFootballFixturesSectionView.isCompetitionOffseason(
            makeSection(matches: [scheduledMatch], errorMessage: nil, isLoading: false, hasLoaded: true)
        ))
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
        matches: [FootballFixtureMatch],
        errorMessage: String?,
        isLoading: Bool,
        hasLoaded: Bool
    ) -> FootballMenuCompetitionSection {
        FootballMenuCompetitionSection(
            competition: .majorLeagueSoccer,
            matches: matches,
            errorMessage: errorMessage,
            isLoading: isLoading,
            hasLoaded: hasLoaded
        )
    }
}
