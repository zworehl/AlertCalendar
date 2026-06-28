import XCTest
@testable import AlertCalendar

final class FootballFixtureCalendarNotesTests: XCTestCase {
    func testCalendarNotesUsePlayerCountryForClubScorers() throws {
        let match = FootballTestData.match(
            id: "club-notes",
            statusState: .finished,
            statusText: "FT",
            homeScore: "2",
            awayScore: "1"
        )
        let scorers = FootballMatchGoalScorers(
            home: [
                FootballMatchGoalScorer(
                    id: "83-34'-0",
                    name: "Raphinha",
                    minute: "34'",
                    countryName: "Brazil"
                ),
                FootballMatchGoalScorer(
                    id: "83-76'-1",
                    name: "Robert Lewandowski",
                    minute: "76'",
                    countryName: "Poland"
                ),
            ],
            away: [
                FootballMatchGoalScorer(
                    id: "132-53'-2",
                    athleteID: "142200",
                    name: "Harry Kane",
                    minute: "53'",
                    countryName: "England",
                    isPenalty: true
                ),
            ]
        )

        let notes = try XCTUnwrap(FootballFixtureFormatter.calendarNotes(for: match, goalScorers: scorers))

        XCTAssertTrue(notes.contains("Goals"))
        XCTAssertTrue(notes.contains("🇧🇷 34' Raphinha"))
        XCTAssertTrue(notes.contains("🇵🇱 76' Robert Lewandowski"))
        XCTAssertTrue(notes.contains("\(FootballFixtureFormatter.flagEmoji(for: "England")) 53' Harry Kane (penalty)"))
        XCTAssertFalse(notes.contains("🇩🇪 53' Harry Kane"))
    }

    func testCalendarNotesDoNotFallbackToClubCountryWhenPlayerCountryIsMissing() throws {
        let match = FootballTestData.match(
            id: "club-notes-missing-country",
            statusState: .finished,
            statusText: "FT",
            homeScore: "0",
            awayScore: "1"
        )
        let scorers = FootballMatchGoalScorers(
            home: [],
            away: [
                FootballMatchGoalScorer(
                    id: "132-18'-0",
                    athleteID: "142200",
                    name: "Harry Kane",
                    minute: "18'"
                ),
            ]
        )

        let notes = try XCTUnwrap(FootballFixtureFormatter.calendarNotes(for: match, goalScorers: scorers))

        XCTAssertTrue(notes.contains("No goals"))
        XCTAssertTrue(notes.contains("🏳️ 18' Harry Kane"))
        XCTAssertFalse(notes.contains("🇩🇪 18' Harry Kane"))
    }

    func testCalendarNotesFallbackToOpposingNationalTeamForOwnGoal() throws {
        let zambia = FootballTestData.nationalTeam(
            id: "zambia-id",
            name: "Zambia",
            abbreviation: "ZAM",
            countryName: "Zambia"
        )
        let match = FootballTestData.friendlyMatch(
            id: "own-goal-notes",
            statusState: .finished,
            statusText: "FT",
            awayTeam: zambia,
            homeScore: "4",
            awayScore: "0"
        )
        let scorers = FootballMatchGoalScorers(
            home: [
                FootballMatchGoalScorer(
                    id: "home-id-68'-0",
                    name: "Dominic Chanda (OG)",
                    minute: "68'",
                    isOwnGoal: true
                ),
            ],
            away: []
        )

        let notes = try XCTUnwrap(FootballFixtureFormatter.calendarNotes(for: match, goalScorers: scorers))

        XCTAssertTrue(notes.contains("🇿🇲 68' Dominic Chanda (own goal)"))
    }
}
