import XCTest
@testable import AlertCalendar

private final class FootballDataAPIClientMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            XCTFail("Missing request handler")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class FootballDataAPIClientTests: XCTestCase {
    override func tearDown() {
        FootballDataAPIClientMockURLProtocol.requestHandler = nil
        super.tearDown()
    }

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

    func testResolvedTeamCountryNamePrefersNationalTeamNameOverVenueCountry() {
        let root: [String: Any] = [
            "displayName": "IR Iran",
            "abbreviation": "IRN",
            "location": "IR Iran",
            "isNational": true,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/fifa.world/venues/7614?lang=en&region=us",
                "address": [
                    "city": "Antalya",
                    "country": "Türkiye",
                ],
            ],
        ]

        XCTAssertEqual(FootballDataAPIClient.resolvedTeamCountryName(from: root), "IR Iran")
    }

    func testResolvedTeamCountryNameInfersNationalTeamWhenESPNMislabelsCountrySideAsClub() {
        let root: [String: Any] = [
            "displayName": "Curacao",
            "abbreviation": "CUR",
            "location": "Curacao",
            "isNational": false,
        ]

        XCTAssertEqual(FootballDataAPIClient.resolvedTeamCountryName(from: root), "Curacao")
    }

    func testResolvedTeamVenueLocationTextKeepsVenueForInferredNationalTeam() {
        let root: [String: Any] = [
            "displayName": "Curacao",
            "abbreviation": "CUR",
            "location": "Curacao",
            "isNational": false,
            "venue": [
                "fullName": "NRG Stadium",
                "address": [
                    "city": "Houston",
                    "state": "Texas",
                    "country": "USA",
                ],
            ],
        ]

        XCTAssertEqual(FootballDataAPIClient.resolvedTeamVenueLocationText(from: root), "NRG Stadium, Houston, Texas, USA")
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

    func testResolvedTeamCountryNameIgnoresTouringVenueCountryForClubs() {
        let root: [String: Any] = [
            "displayName": "Liverpool",
            "abbreviation": "LIV",
            "location": "Liverpool",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/venues/1452?lang=en&region=us",
                "fullName": "Soldier Field",
                "address": [
                    "city": "Chicago",
                    "state": "Illinois",
                    "country": "USA",
                ],
            ],
        ]

        XCTAssertEqual(FootballDataAPIClient.resolvedTeamCountryName(from: root), "England")
    }

    func testResolvedTeamCountryNameKeepsCanadianMLSClubCountry() {
        let root: [String: Any] = [
            "displayName": "Toronto FC",
            "abbreviation": "TOR",
            "location": "Toronto FC",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/usa.1/venues/1845?lang=en&region=us",
                "fullName": "BMO Field",
                "address": [
                    "city": "Toronto",
                    "country": "Canada",
                ],
            ],
        ]

        XCTAssertEqual(FootballDataAPIClient.resolvedTeamCountryName(from: root), "Canada")
    }

    func testResolvedTeamCountryNameKeepsAccentInsensitiveCanadianClubCountry() {
        let root: [String: Any] = [
            "displayName": "CF Montréal",
            "abbreviation": "MTL",
            "location": "CF Montréal",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/usa.1/venues/1830?lang=en&region=us",
                "fullName": "Stade Saputo",
                "address": [
                    "city": "Montreal",
                    "country": "Canada",
                ],
            ],
        ]

        XCTAssertEqual(FootballDataAPIClient.resolvedTeamCountryName(from: root), "Canada")
    }

    func testResolvedTeamVenueLocationTextRejectsTouringClubVenueOutsideDomesticCountry() {
        let root: [String: Any] = [
            "displayName": "Liverpool",
            "abbreviation": "LIV",
            "location": "Liverpool",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/venues/1452?lang=en&region=us",
                "fullName": "Soldier Field",
                "address": [
                    "city": "Chicago",
                    "state": "Illinois",
                    "country": "USA",
                ],
            ],
        ]

        XCTAssertNil(FootballDataAPIClient.resolvedTeamVenueLocationText(from: root))
    }

    func testResolvedTeamVenueLocationTextRejectsForeignVenueWithoutClubLocalitySignals() {
        let root: [String: Any] = [
            "displayName": "Leeds United",
            "abbreviation": "LEE",
            "location": "Leeds United",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/venues/11120?lang=en&region=us",
                "fullName": "Croke Park",
                "address": [
                    "country": "Republic of Ireland",
                ],
            ],
        ]

        XCTAssertNil(FootballDataAPIClient.resolvedTeamVenueLocationText(from: root))
    }

    func testResolvedTeamVenueLocationTextKeepsCanadianMLSClubStadium() {
        let root: [String: Any] = [
            "displayName": "Toronto FC",
            "abbreviation": "TOR",
            "location": "Toronto FC",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/usa.1/venues/1845?lang=en&region=us",
                "fullName": "BMO Field",
                "address": [
                    "city": "Toronto",
                    "country": "Canada",
                ],
            ],
        ]

        XCTAssertEqual(FootballDataAPIClient.resolvedTeamVenueLocationText(from: root), "BMO Field, Toronto, Canada")
    }

    func testResolvedTeamVenueLocationTextKeepsConsistentHomeStadium() {
        let root: [String: Any] = [
            "displayName": "Real Madrid",
            "abbreviation": "RMA",
            "location": "Real Madrid",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/esp.1/venues/10630?lang=en&region=us",
                "fullName": "Santiago Bernabéu",
                "address": [
                    "city": "Madrid",
                    "country": "Spain",
                ],
            ],
        ]

        XCTAssertEqual(
            FootballDataAPIClient.resolvedTeamVenueLocationText(from: root),
            "Santiago Bernabéu, Madrid, Spain"
        )
    }

    func testResolvedTeamVenueLocationTextKeepsJuventusHomeStadium() {
        let root: [String: Any] = [
            "displayName": "Juventus",
            "abbreviation": "JUV",
            "location": "Juventus",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/ita.1/venues/4600?lang=en&region=us",
                "fullName": "Allianz Stadium",
                "address": [
                    "city": "Torino",
                    "country": "Italy",
                ],
            ],
        ]

        XCTAssertEqual(
            FootballDataAPIClient.resolvedTeamVenueLocationText(from: root),
            "Allianz Stadium, Torino, Italy"
        )
    }

    func testResolvedTeamVenueLocationTextKeepsAmericaHomeStadium() {
        let root: [String: Any] = [
            "displayName": "América",
            "abbreviation": "AME",
            "location": "América",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/mex.1/venues/218?lang=en&region=us",
                "fullName": "Estadio Banorte",
                "address": [
                    "city": "Mexico City",
                    "country": "Mexico",
                ],
            ],
        ]

        XCTAssertEqual(
            FootballDataAPIClient.resolvedTeamVenueLocationText(from: root),
            "Estadio Banorte, Mexico City, Mexico"
        )
    }

    func testResolvedTeamVenueLocationTextKeepsGuadalajaraHomeStadium() {
        let root: [String: Any] = [
            "displayName": "Guadalajara",
            "abbreviation": "GDL",
            "location": "Guadalajara",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/mex.1/venues/197?lang=en&region=us",
                "fullName": "Estadio Akron",
                "address": [
                    "city": "Guadalajara",
                    "country": "Mexico",
                ],
            ],
        ]

        XCTAssertEqual(
            FootballDataAPIClient.resolvedTeamVenueLocationText(from: root),
            "Estadio Akron, Guadalajara, Mexico"
        )
    }

    func testResolvedTeamVenueLocationTextKeepsMonterreyHomeStadium() {
        let root: [String: Any] = [
            "displayName": "Monterrey",
            "abbreviation": "MTY",
            "location": "Monterrey",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/mex.1/venues/7540?lang=en&region=us",
                "fullName": "Estadio BBVA",
                "address": [
                    "city": "Guadalupe",
                    "country": "Mexico",
                ],
            ],
        ]

        XCTAssertEqual(
            FootballDataAPIClient.resolvedTeamVenueLocationText(from: root),
            "Estadio BBVA, Guadalupe, Mexico"
        )
    }

    func testResolvedTeamVenueLocationTextKeepsPumasHomeStadium() {
        let root: [String: Any] = [
            "displayName": "Pumas UNAM",
            "abbreviation": "PUM",
            "location": "Pumas UNAM",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/mex.1/venues/234?lang=en&region=us",
                "fullName": "Estadio Olímpico Universitario",
                "address": [
                    "city": "Mexico City",
                    "country": "Mexico",
                ],
            ],
        ]

        XCTAssertEqual(
            FootballDataAPIClient.resolvedTeamVenueLocationText(from: root),
            "Estadio Olímpico Universitario, Mexico City, Mexico"
        )
    }

    func testResolvedTeamVenueLocationTextKeepsTigresHomeStadium() {
        let root: [String: Any] = [
            "displayName": "Tigres UANL",
            "abbreviation": "TIG",
            "location": "Tigres UANL",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/mex.1/venues/240?lang=en&region=us",
                "fullName": "Estadio Universitario",
                "address": [
                    "city": "San Nicolás de los Garza",
                    "country": "Mexico",
                ],
            ],
        ]

        XCTAssertEqual(
            FootballDataAPIClient.resolvedTeamVenueLocationText(from: root),
            "Estadio Universitario, San Nicolás de los Garza, Mexico"
        )
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

    func testBestAvailableLocationTextReturnsNilWhenOnlyPlaceholderVenueExists() {
        let value = FootballDataAPIClient.bestAvailableLocationText(
            reportedLocationText: "Venue TBD",
            fallbackLocationText: nil
        )

        XCTAssertNil(value)
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

    func testFetchGoalScorersDoesNotCacheIncompleteResults() async throws {
        let match = makeMatch(
            id: "goal-cache-match",
            statusState: .inProgress,
            homeScore: "2",
            awayScore: "0"
        )
        let requestLock = NSLock()
        var requestCount = 0
        let session = makeMockSession { request in
            requestLock.lock()
            requestCount += 1
            let currentRequestCount = requestCount
            requestLock.unlock()

            let isCompleteResponse = currentRequestCount > 2
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
                "keyEvents": isCompleteResponse
                    ? [
                        [
                            "scoringPlay": true,
                            "team": ["id": "home-id"],
                            "clock": ["displayValue": "12'"],
                            "type": ["text": "Goal"],
                            "text": "Goal. Lionel Messi (Argentina).",
                        ],
                        [
                            "scoringPlay": true,
                            "team": ["id": "home-id"],
                            "clock": ["displayValue": "81'"],
                            "type": ["text": "Goal"],
                            "text": "Goal. Julian Alvarez (Argentina).",
                        ],
                    ]
                    : [
                        [
                            "scoringPlay": true,
                            "team": ["id": "home-id"],
                            "clock": ["displayValue": "12'"],
                            "type": ["text": "Goal"],
                            "text": "Goal. Lionel Messi (Argentina).",
                        ],
                    ],
            ]
            let data = try JSONSerialization.data(withJSONObject: root)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, data)
        }
        let client = FootballDataAPIClient(session: session)

        let firstFetch = try await client.fetchGoalScorers(for: match)
        let secondFetch = try await client.fetchGoalScorers(for: match)

        XCTAssertEqual(firstFetch?.home.map(\.name), ["Lionel Messi"])
        XCTAssertEqual(secondFetch?.home.map(\.name), ["Lionel Messi", "Julian Alvarez"])
        XCTAssertGreaterThan(requestCount, 2)
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

    func testRefreshStatusesIfNeededCanForceSummaryForFinishedMatchOutsideDefaultWindow() async throws {
        let scheduledStart = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 8 * 60 * 60)
        let actualKickoff = scheduledStart.addingTimeInterval(7 * 60)
        let match = FootballTestData.match(
            id: "finished-force-summary",
            competitionSlug: "fifa.friendly",
            competitionName: "International Friendly",
            startDate: scheduledStart,
            statusState: .finished,
            statusText: "FT",
            homeScore: "0",
            awayScore: "0"
        )
        let session = makeMockSession { request in
            let expectedURL = "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.friendly/summary?event=finished-force-summary"
            XCTAssertEqual(request.url?.absoluteString, expectedURL)

            let body: [String: Any] = [
                "header": [
                    "competitions": [[
                        "status": [
                            "type": [
                                "state": "post",
                                "shortDetail": "FT",
                                "detail": "Full Time",
                                "period": 2,
                            ],
                        ],
                        "competitors": [
                            [
                                "homeAway": "home",
                                "score": "2",
                            ],
                            [
                                "homeAway": "away",
                                "score": "1",
                            ],
                        ],
                    ]],
                ],
                "keyEvents": [
                    [
                        "type": [
                            "text": "Kickoff",
                            "type": "kickoff",
                        ],
                        "wallclock": ISO8601DateFormatter().string(from: actualKickoff),
                    ],
                ],
            ]

            let data = try JSONSerialization.data(withJSONObject: body)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }
        let client = FootballDataAPIClient(session: session)

        let unchanged = await client.refreshStatusesIfNeeded(for: [match])
        XCTAssertNil(unchanged.first?.actualStartDate)

        let refreshed = await client.refreshStatusesIfNeeded(
            for: [match],
            forceSummaryForMatchIDs: [match.id]
        )

        let resolvedKickoff = try XCTUnwrap(refreshed.first?.actualStartDate)
        XCTAssertEqual(resolvedKickoff.timeIntervalSince1970, actualKickoff.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(refreshed.first?.homeScore, "2")
        XCTAssertEqual(refreshed.first?.awayScore, "1")
    }

    func testFetchMatchesDoesNotUseNationalTeamVenueFallbackForWorldCup() async throws {
        let startDate = Date().addingTimeInterval(10 * 24 * 60 * 60)
        let startDateText = ISO8601DateFormatter().string(from: startDate)
        let session = makeMockSession { request in
            let url = try XCTUnwrap(request.url)

            switch url.path {
            case "/apis/site/v2/sports/soccer/fifa.world/scoreboard":
                let body: [String: Any] = [
                    "leagues": [["name": "FIFA World Cup"]],
                    "events": [[
                        "id": "760452",
                        "date": startDateText,
                        "season": ["slug": "fifa-world-cup-test"],
                        "competitions": [[
                            "status": [
                                "type": [
                                    "state": "pre",
                                    "shortDetail": "Scheduled",
                                    "detail": "Scheduled",
                                ],
                            ],
                            "competitors": [
                                [
                                    "homeAway": "home",
                                    "score": "0",
                                    "team": [
                                        "id": "2666",
                                        "displayName": "New Zealand",
                                        "abbreviation": "NZL",
                                    ],
                                ],
                                [
                                    "homeAway": "away",
                                    "score": "0",
                                    "team": [
                                        "id": "2620",
                                        "displayName": "Egypt",
                                        "abbreviation": "EGY",
                                    ],
                                ],
                            ],
                        ]],
                    ]],
                ]
                return try self.jsonResponse(for: request, body: body)
            case "/v2/sports/soccer/teams/2666":
                let body: [String: Any] = [
                    "id": "2666",
                    "displayName": "New Zealand",
                    "location": "New Zealand",
                    "abbreviation": "NZL",
                    "isNational": true,
                    "venue": [
                        "fullName": "Eden Park",
                        "address": [
                            "city": "Auckland",
                            "country": "New Zealand",
                        ],
                    ],
                ]
                return try self.jsonResponse(for: request, body: body)
            case "/v2/sports/soccer/teams/2620":
                let body: [String: Any] = [
                    "id": "2620",
                    "displayName": "Egypt",
                    "location": "Egypt",
                    "abbreviation": "EGY",
                    "isNational": true,
                    "venue": [
                        "fullName": "King Abdullah Sports City",
                        "address": [
                            "city": "Jeddah",
                            "country": "Saudi Arabia",
                        ],
                    ],
                ]
                return try self.jsonResponse(for: request, body: body)
            default:
                XCTFail("Unexpected URL: \(url.absoluteString)")
                throw URLError(.badURL)
            }
        }
        let client = FootballDataAPIClient(session: session)

        let matches = try await client.fetchMatches(for: [.worldCup])

        XCTAssertEqual(matches.count, 1)
        XCTAssertNil(matches.first?.locationText)
    }

    func testFetchMatchesUsesClubVenueFallbackWhenScoreboardVenueIsMissing() async throws {
        let startDate = Date().addingTimeInterval(10 * 24 * 60 * 60)
        let startDateText = ISO8601DateFormatter().string(from: startDate)
        let session = makeMockSession { request in
            let url = try XCTUnwrap(request.url)

            switch url.path {
            case "/apis/site/v2/sports/soccer/usa.1/scoreboard":
                let body: [String: Any] = [
                    "leagues": [["name": "MLS"]],
                    "events": [[
                        "id": "club-match",
                        "date": startDateText,
                        "season": ["slug": "mls-test"],
                        "competitions": [[
                            "status": [
                                "type": [
                                    "state": "pre",
                                    "shortDetail": "Scheduled",
                                    "detail": "Scheduled",
                                ],
                            ],
                            "competitors": [
                                [
                                    "homeAway": "home",
                                    "score": "0",
                                    "team": [
                                        "id": "1845",
                                        "displayName": "Toronto FC",
                                        "abbreviation": "TOR",
                                    ],
                                ],
                                [
                                    "homeAway": "away",
                                    "score": "0",
                                    "team": [
                                        "id": "1850",
                                        "displayName": "Inter Miami CF",
                                        "abbreviation": "MIA",
                                    ],
                                ],
                            ],
                        ]],
                    ]],
                ]
                return try self.jsonResponse(for: request, body: body)
            case "/v2/sports/soccer/teams/1845":
                let body: [String: Any] = [
                    "id": "1845",
                    "displayName": "Toronto FC",
                    "location": "Toronto FC",
                    "abbreviation": "TOR",
                    "isNational": false,
                    "venue": [
                        "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/usa.1/venues/1845?lang=en&region=us",
                        "fullName": "BMO Field",
                        "address": [
                            "city": "Toronto",
                            "country": "Canada",
                        ],
                    ],
                ]
                return try self.jsonResponse(for: request, body: body)
            case "/v2/sports/soccer/teams/1850":
                let body: [String: Any] = [
                    "id": "1850",
                    "displayName": "Inter Miami CF",
                    "location": "Inter Miami CF",
                    "abbreviation": "MIA",
                    "isNational": false,
                ]
                return try self.jsonResponse(for: request, body: body)
            default:
                XCTFail("Unexpected URL: \(url.absoluteString)")
                throw URLError(.badURL)
            }
        }
        let client = FootballDataAPIClient(session: session)

        let matches = try await client.fetchMatches(for: [.majorLeagueSoccer])

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.locationText, "BMO Field, Toronto, Canada")
    }

    private func makeMatch(
        id: String,
        statusState: FootballFixtureStatusState,
        homeScore: String,
        awayScore: String
    ) -> FootballFixtureMatch {
        FootballTestData.friendlyMatch(
            id: id,
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: statusState,
            statusText: "55'",
            homeScore: homeScore,
            awayScore: awayScore
        )
    }

    private func makeMockSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FootballDataAPIClientMockURLProtocol.self]
        FootballDataAPIClientMockURLProtocol.requestHandler = handler
        return URLSession(configuration: configuration)
    }

    private func jsonResponse(
        for request: URLRequest,
        body: [String: Any]
    ) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )
        return (response, data)
    }
}
