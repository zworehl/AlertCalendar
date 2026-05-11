import Foundation
import XCTest
@testable import AlertCalendar

final class FootballDataAPIClientStatisticsParsingTests: FootballDataAPIClientTestCase {
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

    func testSummaryRootIsCoalescedAndReusedAcrossFootballDetails() async throws {
        let match = makeMatch(
            id: "shared-summary-match",
            statusState: .inProgress,
            homeScore: "1",
            awayScore: "0"
        )
        let requestLock = NSLock()
        var requestCount = 0
        let session = makeMockSession { request in
            requestLock.lock()
            requestCount += 1
            requestLock.unlock()

            Thread.sleep(forTimeInterval: 0.05)
            return try self.jsonResponse(
                for: request,
                body: self.summaryRootWithStatsGoalAndFinishedStatus()
            )
        }
        let client = FootballDataAPIClient(session: session)

        async let statisticsTask = client.fetchMatchStatistics(for: match)
        async let scorersTask = client.fetchGoalScorers(for: match)
        let (statistics, scorers) = try await (statisticsTask, scorersTask)
        let refreshed = await client.refreshStatusesIfNeeded(
            for: [match],
            forceSummaryForMatchIDs: [match.id]
        )

        XCTAssertEqual(statistics.count, 10)
        XCTAssertEqual(scorers?.home.map(\.name), ["Lionel Messi"])
        XCTAssertEqual(refreshed.first?.statusState, .finished)
        XCTAssertEqual(refreshed.first?.statusText, "FT")
        XCTAssertEqual(refreshed.first?.homeScore, "1")
        XCTAssertEqual(refreshed.first?.awayScore, "0")

        XCTAssertEqual(requestCount, 1)
    }

    private func summaryRootWithStatsGoalAndFinishedStatus() -> [String: Any] {
        let statistics: [[String: Any]] = [
            ["name": "possessionPct", "displayValue": "61"],
            ["name": "totalShots", "displayValue": "14"],
            ["name": "shotsOnTarget", "displayValue": "6"],
            ["name": "wonCorners", "displayValue": "8"],
            ["name": "offsides", "displayValue": "2"],
            ["name": "foulsCommitted", "displayValue": "11"],
            ["name": "yellowCards", "displayValue": "1"],
            ["name": "redCards", "displayValue": "0"],
            ["name": "saves", "displayValue": "3"],
        ]

        return [
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
                            "score": "1",
                            "team": [
                                "id": "home-id",
                                "displayName": "Argentina",
                            ],
                        ],
                        [
                            "homeAway": "away",
                            "score": "0",
                            "team": [
                                "id": "away-id",
                                "displayName": "Guatemala",
                            ],
                        ],
                    ],
                ]],
            ],
            "boxscore": [
                "teams": [
                    [
                        "homeAway": "home",
                        "team": ["id": "home-id"],
                        "statistics": statistics,
                    ],
                    [
                        "homeAway": "away",
                        "team": ["id": "away-id"],
                        "statistics": statistics,
                    ],
                ],
            ],
            "keyEvents": [
                [
                    "scoringPlay": true,
                    "team": ["id": "home-id"],
                    "clock": ["displayValue": "12'"],
                    "type": ["text": "Goal"],
                    "text": "Goal. Lionel Messi (Argentina).",
                ],
            ],
        ]
    }
}
