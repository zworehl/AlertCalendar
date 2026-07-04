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
}
