import Foundation
import XCTest
@testable import AlertCalendar

final class FootballDataAPIClientGoalScorerParsingTests: FootballDataAPIClientTestCase {
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
        XCTAssertEqual(scorers?.home.map(\.isPenalty), [false, true])
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
        XCTAssertEqual(scorers?.home.map(\.isOwnGoal), [true])
    }

    func testMatchGoalScorersParsesParticipantAthleteID() {
        let match = FootballTestData.match(
            id: "club-goal-match",
            statusState: .finished,
            statusText: "FT",
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
                                "id": "83",
                                "displayName": "Barcelona",
                            ],
                        ],
                        [
                            "homeAway": "away",
                            "team": [
                                "id": "132",
                                "displayName": "Bayern Munich",
                            ],
                        ],
                    ],
                ]],
            ],
            "keyEvents": [
                [
                    "scoringPlay": true,
                    "team": ["id": "132"],
                    "clock": ["displayValue": "18'"],
                    "participants": [
                        ["athlete": ["id": "142200", "displayName": "Harry Kane"]],
                    ],
                    "type": ["text": "Goal - Volley"],
                    "text": "Goal! Barcelona 0, FC Bayern München 1. Harry Kane (FC Bayern München) right footed shot.",
                ],
            ],
        ]

        let scorers = FootballDataAPIClient.matchGoalScorers(from: root, match: match)

        XCTAssertEqual(scorers?.away.first?.name, "Harry Kane")
        XCTAssertEqual(scorers?.away.first?.athleteID, "142200")
        XCTAssertFalse(scorers?.away.first?.isPenalty ?? true)
    }

    func testFetchGoalScorersEnrichesParticipantCountryFromAthleteEndpoint() async throws {
        let match = FootballTestData.match(
            id: "club-goal-country-match",
            statusState: .finished,
            statusText: "FT",
            homeScore: "0",
            awayScore: "1"
        )
        let session = makeMockSession { request in
            let url = try XCTUnwrap(request.url)
            if url.host == "sports.core.api.espn.com" {
                XCTAssertTrue(url.path.hasSuffix("/sports/soccer/athletes/142200"))
                return try self.jsonResponse(
                    for: request,
                    body: [
                        "id": "142200",
                        "displayName": "Harry Kane",
                        "citizenship": "England",
                        "flag": ["alt": "England"],
                    ]
                )
            }

            return try self.jsonResponse(
                for: request,
                body: [
                    "header": [
                        "competitions": [[
                            "competitors": [
                                [
                                    "homeAway": "home",
                                    "team": [
                                        "id": "83",
                                        "displayName": "Barcelona",
                                    ],
                                ],
                                [
                                    "homeAway": "away",
                                    "team": [
                                        "id": "132",
                                        "displayName": "Bayern Munich",
                                    ],
                                ],
                            ],
                        ]],
                    ],
                    "keyEvents": [
                        [
                            "scoringPlay": true,
                            "team": ["id": "132"],
                            "clock": ["displayValue": "18'"],
                            "participants": [
                                ["athlete": ["id": "142200", "displayName": "Harry Kane"]],
                            ],
                            "type": ["text": "Goal"],
                            "text": "Goal! Barcelona 0, FC Bayern München 1. Harry Kane (FC Bayern München) right footed shot.",
                        ],
                    ],
                ]
            )
        }
        let client = FootballDataAPIClient(session: session)

        let scorers = try await client.fetchGoalScorers(for: match)

        XCTAssertEqual(scorers?.away.first?.name, "Harry Kane")
        XCTAssertEqual(scorers?.away.first?.countryName, "England")
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
    }}
