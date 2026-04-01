import XCTest
@testable import AlertCalendar

final class FootballDataAPIClientTests: XCTestCase {
    func testParseEventDateSupportsESPNValuesWithoutSeconds() {
        let date = FootballDataAPIClient.parseEventDate("2026-02-25T22:00Z")

        XCTAssertNotNil(date)
    }

    func testParseEventDateSupportsESPNValuesWithSeconds() {
        let date = FootballDataAPIClient.parseEventDate("2026-02-25T22:00:00Z")

        XCTAssertNotNil(date)
    }

    func testPreferredStatusTextKeepsInterruptedShortDetailOverMinuteDetail() {
        let text = FootballDataAPIClient.preferredStatusText(
            shortDetail: "Delay",
            detail: "11'",
            displayClock: "11:00"
        )

        XCTAssertEqual(text, "Delay")
    }

    func testSupplementalStatusTextPreservesMinuteWhenInterruptedShortDetailWins() {
        let text = FootballDataAPIClient.supplementalStatusText(
            preferredStatusText: "Delay",
            detail: "11'",
            displayClock: "11:00"
        )

        XCTAssertEqual(text, "11'")
    }

    func testResolvedTeamCountryNameFallsBackToDomesticLeagueWhenClubLocationIsJustTheTeamName() {
        let root: [String: Any] = [
            "displayName": "Arsenal",
            "abbreviation": "ARS",
            "location": "Arsenal",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/venues/4228?lang=en&region=us",
                "address": [
                    "city": "Dublin",
                ],
            ],
        ]

        XCTAssertEqual(FootballDataAPIClient.resolvedTeamCountryName(from: root), "England")
    }

    func testResolvedTeamCountryNamePrefersVenueCountryForClubs() {
        let root: [String: Any] = [
            "displayName": "Sporting CP",
            "abbreviation": "SCP",
            "location": "Sporting CP",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/por.1/venues/2352?lang=en&region=us",
                "address": [
                    "city": "Lisbon",
                    "country": "Portugal",
                ],
            ],
        ]

        XCTAssertEqual(FootballDataAPIClient.resolvedTeamCountryName(from: root), "Portugal")
    }

    func testSummaryVenueLocationTextFallsBackToGameInfoVenueWhenHeaderVenueIsMissing() {
        let root: [String: Any] = [
            "gameInfo": [
                "venue": [
                    "fullName": "Alberto Jose Armando (La Bombonera)",
                    "address": [
                        "city": "Buenos Aires",
                        "country": "Argentina",
                    ],
                ],
            ],
        ]
        let competition: [String: Any] = [:]

        let value = FootballDataAPIClient.summaryVenueLocationText(from: root, competition: competition)

        XCTAssertEqual(value, "Alberto Jose Armando (La Bombonera), Buenos Aires, Argentina")
    }

    func testBestAvailableLocationTextPrefersMoreSpecificVenue() {
        let value = FootballDataAPIClient.bestAvailableLocationText(
            reportedLocationText: "Buenos Aires, Argentina",
            fallbackLocationText: "Alberto Jose Armando (La Bombonera), Buenos Aires, Argentina"
        )

        XCTAssertEqual(value, "Alberto Jose Armando (La Bombonera), Buenos Aires, Argentina")
    }

    func testBestAvailableLocationTextReplacesPlaceholderVenue() {
        let value = FootballDataAPIClient.bestAvailableLocationText(
            reportedLocationText: "Alberto Jose Armando (La Bombonera), Buenos Aires, Argentina",
            fallbackLocationText: "TBC"
        )

        XCTAssertEqual(value, "Alberto Jose Armando (La Bombonera), Buenos Aires, Argentina")
    }

    func testMatchGoalScorersParsesHomeAndAwayGoalEvents() {
        let match = makeMatch(
            id: "goal-match",
            statusState: .inProgress,
            homeScore: "2",
            awayScore: "1"
        )
        let root: [String: Any] = [
            "header": [
                "competitions": [[
                    "competitors": [
                        [
                            "homeAway": "home",
                            "team": [
                                "id": "home-id",
                                "displayName": "Argentina",
                            ],
                        ],
                        [
                            "homeAway": "away",
                            "team": [
                                "id": "away-id",
                                "displayName": "Guatemala",
                            ],
                        ],
                    ],
                ]],
            ],
            "keyEvents": [
                [
                    "scoringPlay": true,
                    "team": ["id": "home-id"],
                    "clock": ["displayValue": "12'"],
                    "athletesInvolved": [["displayName": "Lionel Messi"]],
                    "type": ["text": "Goal"],
                    "text": "Goal. Lionel Messi (Argentina).",
                ],
                [
                    "scoringPlay": true,
                    "team": ["id": "away-id"],
                    "clock": ["displayValue": "53'"],
                    "athletesInvolved": [["displayName": "Carlos Mejia"]],
                    "type": ["text": "Goal"],
                    "text": "Goal. Carlos Mejia (Guatemala).",
                ],
                [
                    "scoringPlay": true,
                    "team": ["id": "home-id"],
                    "clock": ["displayValue": "81'"],
                    "athletesInvolved": [["displayName": "Julian Alvarez"]],
                    "type": ["text": "Penalty - Scored"],
                    "text": "Goal. Julian Alvarez (Argentina).",
                ],
            ],
        ]

        let scorers = FootballDataAPIClient.matchGoalScorers(from: root, match: match)

        XCTAssertEqual(scorers?.home.map(\.name), ["Lionel Messi", "Julian Alvarez"])
        XCTAssertEqual(scorers?.away.map(\.name), ["Carlos Mejia"])
        XCTAssertEqual(scorers?.home.map(\.minute), ["12'", "81'"])
    }

    func testMatchGoalScorersReturnsNilWhenScoreIsZeroZero() {
        let match = makeMatch(
            id: "scoreless-match",
            statusState: .inProgress,
            homeScore: "0",
            awayScore: "0"
        )
        let root: [String: Any] = ["keyEvents": []]

        XCTAssertNil(FootballDataAPIClient.matchGoalScorers(from: root, match: match))
    }

    func testMatchGoalScorersParsesNamesFromRealESPNGoalTextWhenAthletesAreMissing() {
        let match = makeMatch(
            id: "goal-text-match",
            statusState: .inProgress,
            homeScore: "0",
            awayScore: "1"
        )
        let root: [String: Any] = [
            "header": [
                "competitions": [[
                    "competitors": [
                        [
                            "homeAway": "home",
                            "team": [
                                "id": "home-id",
                                "displayName": "United States",
                            ],
                        ],
                        [
                            "homeAway": "away",
                            "team": [
                                "id": "away-id",
                                "displayName": "Portugal",
                            ],
                        ],
                    ],
                ]],
            ],
            "keyEvents": [
                [
                    "scoringPlay": true,
                    "team": ["id": "away-id"],
                    "clock": ["displayValue": "37'"],
                    "type": ["text": "Goal"],
                    "text": "Goal! USA 0, Portugal 1. Trincão (Portugal) left footed shot from the centre of the box to the bottom left corner. Assisted by Bruno Fernandes.",
                ],
            ],
        ]

        let scorers = FootballDataAPIClient.matchGoalScorers(from: root, match: match)

        XCTAssertEqual(scorers?.away.map(\.name), ["Trincão"])
        XCTAssertEqual(scorers?.away.map(\.minute), ["37'"])
    }

    func testMatchGoalScorersParsesOwnGoalTextFromRealESPNFormat() {
        let match = makeMatch(
            id: "own-goal-text-match",
            statusState: .inProgress,
            homeScore: "4",
            awayScore: "0"
        )
        let root: [String: Any] = [
            "header": [
                "competitions": [[
                    "competitors": [
                        [
                            "homeAway": "home",
                            "team": [
                                "id": "home-id",
                                "displayName": "Argentina",
                            ],
                        ],
                        [
                            "homeAway": "away",
                            "team": [
                                "id": "away-id",
                                "displayName": "Zambia",
                            ],
                        ],
                    ],
                ]],
            ],
            "keyEvents": [
                [
                    "scoringPlay": true,
                    "team": ["id": "home-id"],
                    "clock": ["displayValue": "68'"],
                    "type": ["text": "Own Goal"],
                    "text": "Own Goal by Dominic Chanda, Zambia. Argentina 4, Zambia 0.",
                ],
            ],
        ]

        let scorers = FootballDataAPIClient.matchGoalScorers(from: root, match: match)

        XCTAssertEqual(scorers?.home.map(\.name), ["Dominic Chanda (OG)"])
        XCTAssertEqual(scorers?.home.map(\.minute), ["68'"])
    }

    func testMatchStatisticsParsesPreferredStatsAndSubstitutions() {
        let root: [String: Any] = [
            "boxscore": [
                "teams": [
                    [
                        "homeAway": "home",
                        "team": ["id": "home-id"],
                        "statistics": [
                            ["name": "possessionPct", "displayValue": "61"],
                            ["name": "totalShots", "displayValue": "14"],
                            ["name": "shotsOnTarget", "displayValue": "6"],
                            ["name": "wonCorners", "displayValue": "8"],
                            ["name": "offsides", "displayValue": "2"],
                            ["name": "foulsCommitted", "displayValue": "11"],
                            ["name": "yellowCards", "displayValue": "1"],
                            ["name": "redCards", "displayValue": "0"],
                            ["name": "saves", "displayValue": "3"],
                        ],
                    ],
                    [
                        "homeAway": "away",
                        "team": ["id": "away-id"],
                        "statistics": [
                            ["name": "possessionPct", "displayValue": "39"],
                            ["name": "totalShots", "displayValue": "7"],
                            ["name": "shotsOnTarget", "displayValue": "2"],
                            ["name": "wonCorners", "displayValue": "3"],
                            ["name": "offsides", "displayValue": "1"],
                            ["name": "foulsCommitted", "displayValue": "9"],
                            ["name": "yellowCards", "displayValue": "2"],
                            ["name": "redCards", "displayValue": "1"],
                            ["name": "saves", "displayValue": "5"],
                        ],
                    ],
                ],
            ],
            "keyEvents": [
                ["type": ["type": "substitution"], "team": ["id": "home-id"]],
                ["type": ["type": "substitution"], "team": ["id": "home-id"]],
                ["type": ["type": "substitution"], "team": ["id": "away-id"]],
            ],
        ]

        let statistics = FootballDataAPIClient.matchStatistics(from: root)

        XCTAssertEqual(statistics.map(\.id), [
            "possessionpct",
            "totalshots",
            "shotsontarget",
            "woncorners",
            "offsides",
            "foulscommitted",
            "yellowcards",
            "redcards",
            "saves",
            "substitutions",
        ])
        XCTAssertEqual(statistics.first?.homeValue, "61%")
        XCTAssertEqual(statistics.first?.awayValue, "39%")
        XCTAssertEqual(statistics.last?.label, "Substitutions")
        XCTAssertEqual(statistics.last?.homeValue, "2")
        XCTAssertEqual(statistics.last?.awayValue, "1")
    }

    func testMatchStatisticsReturnsEmptyWhenBoxscoreIsMissing() {
        XCTAssertTrue(FootballDataAPIClient.matchStatistics(from: [:]).isEmpty)
    }

    func testActualKickoffDateUsesKickoffWallclockWithinReasonableWindow() {
        let fallbackStartDate = FootballDataAPIClient.parseEventDate("2025-03-31T23:00:00Z")!
        let root: [String: Any] = [
            "keyEvents": [
                [
                    "type": ["text": "Kickoff"],
                    "wallclock": "2025-03-31T23:07:54Z",
                ],
            ],
        ]

        let kickoffDate = FootballDataAPIClient.actualKickoffDate(
            from: root,
            fallbackStartDate: fallbackStartDate
        )

        XCTAssertEqual(kickoffDate, FootballDataAPIClient.parseEventDate("2025-03-31T23:07:54Z"))
    }

    func testActualKickoffDateRejectsOutlierKickoffWallclock() {
        let fallbackStartDate = FootballDataAPIClient.parseEventDate("2025-03-31T23:00:00Z")!
        let root: [String: Any] = [
            "keyEvents": [
                [
                    "type": ["text": "Kickoff"],
                    "wallclock": "2025-04-01T04:45:00Z",
                ],
            ],
        ]

        XCTAssertNil(
            FootballDataAPIClient.actualKickoffDate(
                from: root,
                fallbackStartDate: fallbackStartDate
            )
        )
    }

    private func makeMatch(
        id: String,
        statusState: FootballFixtureStatusState,
        homeScore: String,
        awayScore: String
    ) -> FootballFixtureMatch {
        FootballFixtureMatch(
            id: id,
            competitionSlug: "fifa.friendly",
            competitionName: "International Friendly",
            competitionStage: nil,
            competitionLogoURL: nil,
            locationText: nil,
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: statusState,
            statusText: "55'",
            homeTeam: FootballTeamSummary(
                id: "home-id",
                name: "Argentina",
                abbreviation: "ARG",
                logoURL: nil,
                countryName: "Argentina",
                isNational: true
            ),
            awayTeam: FootballTeamSummary(
                id: "away-id",
                name: "Guatemala",
                abbreviation: "GUA",
                logoURL: nil,
                countryName: "Guatemala",
                isNational: true
            ),
            homeScore: homeScore,
            awayScore: awayScore
        )
    }
}
