import XCTest
@testable import AlertCalendar

final class SettingsFootballFixturesFeedbackTests: XCTestCase {
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
