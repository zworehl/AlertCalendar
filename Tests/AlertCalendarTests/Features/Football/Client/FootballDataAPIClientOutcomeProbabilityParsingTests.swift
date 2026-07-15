import XCTest
@testable import AlertCalendar

final class FootballDataAPIClientOutcomeProbabilityParsingTests: FootballDataAPIClientTestCase {
    func testParsesScoreboardMoneylineOddsAndNormalizesOverround() throws {
        let root: [String: Any] = [
            "odds": [
                [
                    "provider": [
                        "displayName": "DraftKings",
                        "priority": 1,
                    ],
                    "moneyline": [
                        "home": ["close": ["odds": "-650"]],
                        "draw": ["close": ["odds": "+650"]],
                        "away": ["close": ["odds": "+1400"]],
                    ],
                ],
            ],
        ]

        let probabilities = try XCTUnwrap(FootballDataAPIClient.matchOutcomeProbabilities(from: root))

        XCTAssertEqual(probabilities.source, FootballMatchOutcomeProbabilitySource.marketOdds)
        XCTAssertEqual(probabilities.providerName, "DraftKings")
        XCTAssertEqual(probabilities.homeWin, 0.8125, accuracy: 0.0001)
        XCTAssertEqual(probabilities.draw, 0.1250, accuracy: 0.0001)
        XCTAssertEqual(probabilities.awayWin, 0.0625, accuracy: 0.0001)
    }

    func testPrefersLiveSummaryOddsWhenAvailable() throws {
        let root: [String: Any] = [
            "odds": [
                [
                    "provider": [
                        "name": "ESPN BET",
                        "priority": 0,
                    ],
                    "homeTeamOdds": [
                        "current": ["moneyLine": ["value": 2.65]],
                    ],
                    "awayTeamOdds": [
                        "current": ["moneyLine": ["value": 2.95]],
                    ],
                    "drawOdds": ["moneyLine": 190],
                ],
                [
                    "provider": [
                        "name": "ESPN BET - Live Odds",
                        "priority": 0,
                    ],
                    "homeTeamOdds": [
                        "current": ["moneyLine": ["value": 16.0]],
                    ],
                    "awayTeamOdds": [
                        "current": ["moneyLine": ["value": 22.0]],
                    ],
                    "drawOdds": ["moneyLine": -3000],
                ],
            ],
        ]

        let probabilities = try XCTUnwrap(FootballDataAPIClient.matchOutcomeProbabilities(from: root))

        XCTAssertEqual(probabilities.source, FootballMatchOutcomeProbabilitySource.liveMarketOdds)
        XCTAssertEqual(probabilities.providerName, "ESPN BET - Live Odds")
        XCTAssertGreaterThan(probabilities.draw, 0.85)
        XCTAssertLessThan(probabilities.homeWin, 0.10)
        XCTAssertLessThan(probabilities.awayWin, 0.10)
    }

    func testParsesDecimalTeamOddsAndDrawDecimalOdds() throws {
        let root: [String: Any] = [
            "odds": [
                [
                    "provider": [
                        "name": "ESPN BET",
                        "priority": 0,
                    ],
                    "homeTeamOdds": [
                        "current": ["moneyLine": ["value": 2.5]],
                    ],
                    "awayTeamOdds": [
                        "current": ["moneyLine": ["value": 4.0]],
                    ],
                    "current": [
                        "draw": ["value": 3.2],
                    ],
                ],
            ],
        ]

        let probabilities = try XCTUnwrap(FootballDataAPIClient.matchOutcomeProbabilities(from: root))
        let expectedTotal = (1 / 2.5) + (1 / 3.2) + (1 / 4.0)

        XCTAssertEqual(probabilities.homeWin, (1 / 2.5) / expectedTotal, accuracy: 0.0001)
        XCTAssertEqual(probabilities.draw, (1 / 3.2) / expectedTotal, accuracy: 0.0001)
        XCTAssertEqual(probabilities.awayWin, (1 / 4.0) / expectedTotal, accuracy: 0.0001)
    }

    func testPrefersCurrentMoneylineOverCloseAndOpenQuotes() throws {
        let root: [String: Any] = [
            "odds": [
                [
                    "provider": ["name": "Current Market"],
                    "moneyline": [
                        "home": [
                            "current": ["moneyLine": ["value": 2.0]],
                            "close": ["odds": "-900"],
                            "open": ["odds": "-800"],
                        ],
                        "draw": [
                            "current": ["moneyLine": ["value": 4.0]],
                            "close": ["odds": "+1200"],
                            "open": ["odds": "+1100"],
                        ],
                        "away": [
                            "current": ["moneyLine": ["value": 4.0]],
                            "close": ["odds": "+1400"],
                            "open": ["odds": "+1300"],
                        ],
                    ],
                ],
            ],
        ]

        let probabilities = try XCTUnwrap(FootballDataAPIClient.matchOutcomeProbabilities(from: root))

        XCTAssertEqual(probabilities.homeWin, 0.50, accuracy: 0.0001)
        XCTAssertEqual(probabilities.draw, 0.25, accuracy: 0.0001)
        XCTAssertEqual(probabilities.awayWin, 0.25, accuracy: 0.0001)
    }

    func testAttachesObservedMatchStateAndDetectsStructuredLiveMarket() throws {
        let observedAt = Date(timeIntervalSince1970: 1_752_600_000)
        let competition: [String: Any] = [
            "status": [
                "type": [
                    "state": "in",
                    "period": 2,
                ],
            ],
            "competitors": [
                ["homeAway": "home", "score": "1"],
                ["homeAway": "away", "score": "2"],
            ],
        ]
        let root: [String: Any] = [
            "odds": [
                [
                    "provider": ["name": "Bet 365", "priority": 0],
                    "bettingOdds": ["teamOdds": [:]],
                    "homeTeamOdds": ["odds": ["value": 401.0]],
                    "drawOdds": ["value": 13.0],
                    "awayTeamOdds": ["odds": ["value": 1.04]],
                ],
            ],
        ]

        let probabilities = try XCTUnwrap(
            FootballDataAPIClient.matchOutcomeProbabilities(
                from: root,
                competition: competition,
                observedAt: observedAt
            )
        )

        XCTAssertEqual(probabilities.source, .liveMarketOdds)
        XCTAssertEqual(probabilities.observedAt, observedAt)
        XCTAssertEqual(probabilities.observedHomeScore, 1)
        XCTAssertEqual(probabilities.observedAwayScore, 2)
        XCTAssertEqual(probabilities.observedStatusPeriod, 2)
        XCTAssertGreaterThan(probabilities.awayWin, 0.90)
    }

    func testProviderUpdateTimestampTakesPrecedenceOverLocalObservationTime() throws {
        let localObservation = Date(timeIntervalSince1970: 1_752_600_000)
        let providerObservation = try XCTUnwrap(
            FootballDataAPIClient.parseEventDate("2025-07-15T12:00:00Z")
        )
        let competition: [String: Any] = [
            "status": ["type": ["state": "in", "period": 2]],
            "competitors": [
                ["homeAway": "home", "score": "1"],
                ["homeAway": "away", "score": "0"],
            ],
        ]
        let root: [String: Any] = [
            "odds": [[
                "isLive": true,
                "lastUpdated": "2025-07-15T12:00:00Z",
                "moneyline": [
                    "home": ["current": ["moneyLine": ["value": 1.5]]],
                    "draw": ["current": ["moneyLine": ["value": 4.0]]],
                    "away": ["current": ["moneyLine": ["value": 7.0]]],
                ],
            ]],
        ]

        let probabilities = try XCTUnwrap(
            FootballDataAPIClient.matchOutcomeProbabilities(
                from: root,
                competition: competition,
                observedAt: localObservation
            )
        )

        XCTAssertEqual(probabilities.observedAt, providerObservation)
    }

    func testReturnsNilWhenSuccessfulPayloadHasNoMarket() {
        let root: [String: Any] = [
            "header": [
                "competitions": [[
                    "status": ["type": ["state": "in", "period": 2]],
                    "competitors": [
                        ["homeAway": "home", "score": "1"],
                        ["homeAway": "away", "score": "2"],
                    ],
                ]],
            ],
        ]

        XCTAssertNil(FootballDataAPIClient.matchOutcomeProbabilities(from: root))
    }

    func testLiveMarketAlwaysRanksAheadOfPregameProviderPriority() throws {
        let competition: [String: Any] = [
            "status": ["type": ["state": "in", "period": 2]],
            "competitors": [
                ["homeAway": "home", "score": "1"],
                ["homeAway": "away", "score": "1"],
            ],
        ]
        let root: [String: Any] = [
            "odds": [
                [
                    "provider": ["name": "Pregame", "priority": 0],
                    "moneyline": [
                        "home": ["close": ["odds": "-200"]],
                        "draw": ["close": ["odds": "+300"]],
                        "away": ["close": ["odds": "+500"]],
                    ],
                ],
                [
                    "provider": ["name": "Live Feed", "priority": 99],
                    "isLive": true,
                    "moneyline": [
                        "home": ["current": ["moneyLine": ["value": 3.0]]],
                        "draw": ["current": ["moneyLine": ["value": 2.0]]],
                        "away": ["current": ["moneyLine": ["value": 6.0]]],
                    ],
                ],
            ],
        ]

        let probabilities = try XCTUnwrap(
            FootballDataAPIClient.matchOutcomeProbabilities(from: root, competition: competition)
        )

        XCTAssertEqual(probabilities.source, .liveMarketOdds)
        XCTAssertEqual(probabilities.providerName, "Live Feed")
        let pregame = try XCTUnwrap(
            FootballDataAPIClient.pregameOutcomeProbabilities(from: root, competition: competition)
        )
        XCTAssertEqual(pregame.source, .marketOdds)
        XCTAssertEqual(pregame.providerName, "Pregame")
    }

    func testSuspendedLiveMarketIsNotParsed() {
        let root: [String: Any] = [
            "odds": [[
                "provider": ["name": "Example Live"],
                "isLive": true,
                "status": ["state": "suspended"],
                "moneyline": [
                    "home": ["current": ["moneyLine": ["value": 2.0]]],
                    "draw": ["current": ["moneyLine": ["value": 3.0]]],
                    "away": ["current": ["moneyLine": ["value": 4.0]]],
                ],
            ]],
        ]

        XCTAssertNil(FootballDataAPIClient.matchOutcomeProbabilities(from: root))
    }

    func testUnavailableLiveSignalWinsOverConflictingOpenSignal() {
        let root: [String: Any] = [
            "odds": [[
                "provider": ["name": "Example Live"],
                "isLive": true,
                "state": "open",
                "market": ["status": "suspended"],
                "moneyline": [
                    "home": ["current": ["moneyLine": ["value": 2.0]]],
                    "draw": ["current": ["moneyLine": ["value": 3.0]]],
                    "away": ["current": ["moneyLine": ["value": 4.0]]],
                ],
            ]],
        ]

        XCTAssertNil(FootballDataAPIClient.matchOutcomeProbabilities(from: root))
    }

    func testLiveNamedProviderRemainsPregameWhileMatchIsScheduled() throws {
        let competition: [String: Any] = [
            "status": ["type": ["state": "pre"]],
            "competitors": [
                ["homeAway": "home", "score": "0"],
                ["homeAway": "away", "score": "0"],
            ],
        ]
        let root: [String: Any] = [
            "odds": [[
                "provider": ["name": "Example Live Odds"],
                "isLive": true,
                "moneyline": [
                    "home": ["current": ["moneyLine": ["value": 2.0]]],
                    "draw": ["current": ["moneyLine": ["value": 3.0]]],
                    "away": ["current": ["moneyLine": ["value": 4.0]]],
                ],
            ]],
        ]

        let probabilities = try XCTUnwrap(
            FootballDataAPIClient.matchOutcomeProbabilities(from: root, competition: competition)
        )

        XCTAssertEqual(probabilities.source, .marketOdds)
    }

    func testSuccessfulSummaryWithoutMarketClearsPreviousLiveQuote() async throws {
        let liveProbabilities = try XCTUnwrap(
            FootballMatchOutcomeProbabilities(
                homeWin: 0.45,
                draw: 0.16,
                awayWin: 0.39,
                source: .liveMarketOdds,
                scope: .regulationTime
            )
        )
        let match = FootballTestData.match(
            id: "live-odds-removed",
            competitionSlug: "fifa.world",
            competitionName: "FIFA World Cup",
            startDate: AlertCalendarClock.nowRoundedToSecond().addingTimeInterval(-90 * 60),
            statusState: .inProgress,
            statusText: "90'+6'",
            statusPeriod: 2,
            homeScore: "1",
            awayScore: "2",
            outcomeProbabilities: liveProbabilities
        )
        let session = makeMockSession { request in
            try self.jsonResponse(
                for: request,
                body: [
                    "header": [
                        "competitions": [[
                            "status": [
                                "displayClock": "90'+6'",
                                "type": [
                                    "state": "in",
                                    "shortDetail": "90'+6'",
                                    "period": 2,
                                ],
                            ],
                            "competitors": [
                                ["homeAway": "home", "score": "1"],
                                ["homeAway": "away", "score": "2"],
                            ],
                        ]],
                    ],
                ]
            )
        }

        let client = FootballDataAPIClient(session: session)
        let refreshed = await client.refreshStatusesIfNeeded(for: [match])

        XCTAssertNil(try XCTUnwrap(refreshed.first).outcomeProbabilities)
    }

    func testScoreboardMergeClearsMissingLiveQuoteButPreservesPregameQuote() throws {
        let liveProbabilities = try XCTUnwrap(
            FootballMatchOutcomeProbabilities(
                homeWin: 0.45,
                draw: 0.16,
                awayWin: 0.39,
                source: .liveMarketOdds,
                scope: .regulationTime
            )
        )
        let pregameProbabilities = try XCTUnwrap(
            FootballMatchOutcomeProbabilities(
                homeWin: 0.40,
                draw: 0.30,
                awayWin: 0.30,
                source: .marketOdds,
                scope: .regulationTime
            )
        )
        let current = FootballTestData.match(
            id: "scoreboard-market-removal",
            statusState: .inProgress,
            statusText: "60'"
        )

        let previousLive = FootballTestData.match(
            id: current.id,
            statusState: .inProgress,
            statusText: "59'",
            pregameOutcomeProbabilities: pregameProbabilities,
            outcomeProbabilities: liveProbabilities
        )
        let mergedLive = CalendarMonitor.footballMatchPreservingKnownTimingContext(
            current,
            previousMatch: previousLive
        )
        XCTAssertNil(mergedLive.outcomeProbabilities)
        XCTAssertEqual(mergedLive.pregameOutcomeProbabilities, pregameProbabilities)

        let previousPregame = FootballTestData.match(
            id: current.id,
            statusState: .inProgress,
            statusText: "59'",
            outcomeProbabilities: pregameProbabilities
        )
        let mergedPregame = CalendarMonitor.footballMatchPreservingKnownTimingContext(
            current,
            previousMatch: previousPregame
        )
        XCTAssertEqual(mergedPregame.outcomeProbabilities, pregameProbabilities)
    }
}
