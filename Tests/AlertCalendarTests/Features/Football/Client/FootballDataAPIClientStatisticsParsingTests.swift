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
    func testActualEndDateUsesEndRegularTimeWallclock() {
        let fallbackStartDate = FootballDataAPIClient.parseEventDate("2026-06-14T23:00:00Z")!
        let actualKickoff = FootballDataAPIClient.parseEventDate("2026-06-14T23:03:28Z")!
        let actualEnd = FootballDataAPIClient.parseEventDate("2026-06-15T01:04:09Z")!
        let root: [String: Any] = [
            "keyEvents": [
                [
                    "type": [
                        "text": "End Delay",
                        "type": "end-delay",
                    ],
                    "wallclock": "2026-06-14T23:30:18Z",
                ],
                [
                    "type": [
                        "text": "End Regular Time",
                        "type": "end-regular-time",
                    ],
                    "wallclock": "2026-06-15T01:04:09Z",
                ],
            ],
        ]

        let endDate = FootballDataAPIClient.actualEndDate(
            from: root,
            fallbackStartDate: fallbackStartDate,
            actualStartDate: actualKickoff,
            statusPeriod: 2
        )

        XCTAssertEqual(endDate, actualEnd)
    }
    func testActualEndDateDoesNotUseRegularTimeForExtraTimeFinish() {
        let fallbackStartDate = FootballDataAPIClient.parseEventDate("2026-06-14T23:00:00Z")!
        let actualKickoff = FootballDataAPIClient.parseEventDate("2026-06-14T23:03:28Z")!
        let root: [String: Any] = [
            "keyEvents": [
                [
                    "type": [
                        "text": "End Regular Time",
                        "type": "end-regular-time",
                    ],
                    "wallclock": "2026-06-15T01:04:09Z",
                ],
            ],
        ]

        let endDate = FootballDataAPIClient.actualEndDate(
            from: root,
            fallbackStartDate: fallbackStartDate,
            actualStartDate: actualKickoff,
            statusPeriod: 4
        )

        XCTAssertNil(endDate)
    }

    func testActualEndDateUsesGenericEndMatchForPenaltyShootout() {
        let fallbackStartDate = FootballDataAPIClient.parseEventDate("2022-12-18T15:00:00Z")!
        let actualKickoff = FootballDataAPIClient.parseEventDate("2022-12-18T15:02:00Z")!
        let shootoutEnd = FootballDataAPIClient.parseEventDate("2022-12-18T17:55:00Z")!
        let root: [String: Any] = [
            "keyEvents": [
                [
                    "type": ["text": "End Extra Time", "type": "end-extra-time"],
                    "wallclock": "2022-12-18T17:42:00Z",
                ],
                [
                    "type": ["text": "End Match", "type": "end-match"],
                    "wallclock": "2022-12-18T17:55:00Z",
                ],
            ],
        ]

        let endDate = FootballDataAPIClient.actualEndDate(
            from: root,
            fallbackStartDate: fallbackStartDate,
            actualStartDate: actualKickoff,
            statusPeriod: 5
        )

        XCTAssertEqual(endDate, shootoutEnd)
    }

    func testSummarySnapshotUsesKnownPeriodWhenPenaltySummaryOmitsIt() throws {
        let fallbackStartDate = FootballDataAPIClient.parseEventDate("2022-12-18T15:00:00Z")!
        let shootoutEnd = FootballDataAPIClient.parseEventDate("2022-12-18T17:55:00Z")!
        let root: [String: Any] = [
            "header": [
                "competitions": [[
                    "status": ["type": ["state": "post", "shortDetail": "FT-Pens"]],
                    "competitors": [
                        ["homeAway": "home", "score": "3", "winner": true, "shootoutScore": 4],
                        ["homeAway": "away", "score": "3", "winner": false, "shootoutScore": 2],
                    ],
                ]],
            ],
            "keyEvents": [[
                "type": ["text": "End Match", "type": "end-match"],
                "wallclock": "2022-12-18T17:55:00Z",
            ]],
        ]

        let snapshot = try XCTUnwrap(
            FootballDataAPIClient.summarySnapshot(
                from: root,
                fallbackStartDate: fallbackStartDate,
                fallbackStatusPeriod: 5
            )
        )

        XCTAssertEqual(snapshot.statusPeriod, 5)
        XCTAssertEqual(snapshot.actualEndDate, shootoutEnd)
        XCTAssertEqual(snapshot.officialWinner, .home)
        XCTAssertEqual(snapshot.homeShootoutScore, 4)
        XCTAssertEqual(snapshot.awayShootoutScore, 2)
    }
    func testRefreshStatusesIfNeededCanForceSummaryForFinishedMatchOutsideDefaultWindow() async throws {
        let scheduledStart = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 8 * 60 * 60)
        let actualKickoff = scheduledStart.addingTimeInterval(7 * 60)
        let actualEnd = actualKickoff.addingTimeInterval(120 * 60)
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
                    [
                        "type": [
                            "text": "End Regular Time",
                            "type": "end-regular-time",
                        ],
                        "wallclock": ISO8601DateFormatter().string(from: actualEnd),
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
        let resolvedEnd = try XCTUnwrap(refreshed.first?.actualEndDate)
        XCTAssertEqual(resolvedEnd.timeIntervalSince1970, actualEnd.timeIntervalSince1970, accuracy: 0.001)
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
