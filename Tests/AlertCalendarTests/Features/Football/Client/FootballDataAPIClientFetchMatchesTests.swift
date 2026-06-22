import Foundation
import XCTest
@testable import AlertCalendar

final class FootballDataAPIClientFetchMatchesTests: FootballDataAPIClientTestCase {
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

    func testFetchMatchesUsesCountryFlagsForNationalCompetitionWithoutEnrichment() async throws {
        let startDate = Date().addingTimeInterval(6 * 60 * 60)
        let startDateText = ISO8601DateFormatter().string(from: startDate)
        let session = makeMockSession { request in
            let url = try XCTUnwrap(request.url)
            guard url.path == "/apis/site/v2/sports/soccer/fifa.friendly/scoreboard" else {
                XCTFail("Unexpected URL: \(url.absoluteString)")
                throw URLError(.badURL)
            }

            let body: [String: Any] = [
                "leagues": [["name": "FIFA Friendlies"]],
                "events": [[
                    "id": "usa-spain",
                    "date": startDateText,
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
                                    "id": "2642",
                                    "displayName": "United States",
                                    "abbreviation": "USA",
                                    "logo": "https://a.espncdn.com/i/teamlogos/countries/500/usa.png",
                                ],
                            ],
                            [
                                "homeAway": "away",
                                "score": "0",
                                "team": [
                                    "id": "2650",
                                    "displayName": "Spain",
                                    "abbreviation": "ESP",
                                    "logo": "https://a.espncdn.com/i/teamlogos/countries/500/esp.png",
                                ],
                            ],
                        ],
                    ]],
                ]],
            ]
            return try self.jsonResponse(for: request, body: body)
        }
        let competition = FootballCompetitionPreset(
            slug: "fifa.friendly",
            title: "FIFA Friendlies",
            lookbackDays: 0,
            lookaheadDays: 1,
            category: .nationalTeams,
            region: .global
        )
        let client = FootballDataAPIClient(session: session)

        let matches = try await client.fetchMatches(
            for: [competition],
            enrichTeams: false
        )

        let match = try XCTUnwrap(matches.first)
        XCTAssertTrue(match.homeTeam.isNational)
        XCTAssertTrue(match.awayTeam.isNational)
        XCTAssertEqual(
            match.homeTeam.logoURL?.absoluteString,
            "https://a.espncdn.com/i/teamlogos/countries/500/usa.png"
        )
        XCTAssertEqual(
            match.awayTeam.logoURL?.absoluteString,
            "https://a.espncdn.com/i/teamlogos/countries/500/esp.png"
        )
    }

    func testFetchMatchesUsesPresetCategoryForCustomNationalCompetitionFlags() async throws {
        let startDate = Date().addingTimeInterval(6 * 60 * 60)
        let startDateText = ISO8601DateFormatter().string(from: startDate)
        let session = makeMockSession { request in
            let url = try XCTUnwrap(request.url)
            guard url.path == "/apis/site/v2/sports/soccer/custom.national/scoreboard" else {
                XCTFail("Unexpected URL: \(url.absoluteString)")
                throw URLError(.badURL)
            }

            let body: [String: Any] = [
                "leagues": [["name": "Custom National Cup"]],
                "events": [[
                    "id": "crc-mex",
                    "date": startDateText,
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
                                    "id": "2677",
                                    "displayName": "Costa Rica",
                                    "abbreviation": "CRC",
                                    "logo": "https://a.espncdn.com/i/teamlogos/countries/500/crc.png",
                                ],
                            ],
                            [
                                "homeAway": "away",
                                "score": "0",
                                "team": [
                                    "id": "2634",
                                    "displayName": "Mexico",
                                    "abbreviation": "MEX",
                                    "logo": "https://a.espncdn.com/i/teamlogos/countries/500/mex.png",
                                ],
                            ],
                        ],
                    ]],
                ]],
            ]
            return try self.jsonResponse(for: request, body: body)
        }
        let competition = FootballCompetitionPreset(
            slug: "custom.national",
            title: "Custom National Cup",
            lookbackDays: 0,
            lookaheadDays: 1,
            category: .nationalTeams,
            region: .global
        )
        let client = FootballDataAPIClient(session: session)

        let matches = try await client.fetchMatches(
            for: [competition],
            enrichTeams: false
        )

        let match = try XCTUnwrap(matches.first)
        XCTAssertEqual(
            match.homeTeam.logoURL?.absoluteString,
            "https://a.espncdn.com/i/teamlogos/countries/500/crc.png"
        )
        XCTAssertEqual(
            match.awayTeam.logoURL?.absoluteString,
            "https://a.espncdn.com/i/teamlogos/countries/500/mex.png"
        )
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
    func testFetchMatchesParsesSecondLegAggregateContext() async throws {
        let startDate = Date().addingTimeInterval(24 * 60 * 60)
        let startDateText = ISO8601DateFormatter().string(from: startDate)
        let session = makeMockSession { request in
            let url = try XCTUnwrap(request.url)

            switch url.path {
            case "/apis/site/v2/sports/soccer/uefa.champions/scoreboard":
                let body: [String: Any] = [
                    "leagues": [[
                        "name": "UEFA Champions League",
                        "season": [
                            "type": [
                                "name": "Quarterfinals",
                            ],
                        ],
                    ]],
                    "events": [[
                        "id": "second-leg-match",
                        "date": startDateText,
                        "season": ["slug": "quarterfinals"],
                        "competitions": [[
                            "status": [
                                "type": [
                                    "state": "pre",
                                    "shortDetail": "Scheduled",
                                    "detail": "Scheduled",
                                ],
                            ],
                            "leg": [
                                "value": 2,
                                "displayValue": "2nd Leg",
                            ],
                            "series": [
                                "title": "Quarterfinals",
                                "totalCompetitions": 2,
                                "competitors": [
                                    [
                                        "id": "1068",
                                        "aggregateScore": 2,
                                    ],
                                    [
                                        "id": "83",
                                        "aggregateScore": 0,
                                    ],
                                ],
                            ],
                            "notes": [[
                                "headline": "2nd Leg - Atlético Madrid lead 2-0 on aggregate",
                            ]],
                            "competitors": [
                                [
                                    "id": "1068",
                                    "homeAway": "home",
                                    "score": "0",
                                    "aggregateScore": 2,
                                    "team": [
                                        "id": "1068",
                                        "displayName": "Atlético Madrid",
                                        "abbreviation": "ATM",
                                    ],
                                ],
                                [
                                    "id": "83",
                                    "homeAway": "away",
                                    "score": "0",
                                    "aggregateScore": 0,
                                    "team": [
                                        "id": "83",
                                        "displayName": "Barcelona",
                                        "abbreviation": "BAR",
                                    ],
                                ],
                            ],
                        ]],
                    ]],
                ]
                return try self.jsonResponse(for: request, body: body)
            case "/v2/sports/soccer/teams/1068":
                let body: [String: Any] = [
                    "id": "1068",
                    "displayName": "Atlético Madrid",
                    "location": "Atlético Madrid",
                    "abbreviation": "ATM",
                    "isNational": false,
                ]
                return try self.jsonResponse(for: request, body: body)
            case "/v2/sports/soccer/teams/83":
                let body: [String: Any] = [
                    "id": "83",
                    "displayName": "Barcelona",
                    "location": "Barcelona",
                    "abbreviation": "BAR",
                    "isNational": false,
                ]
                return try self.jsonResponse(for: request, body: body)
            default:
                XCTFail("Unexpected URL: \(url.absoluteString)")
                throw URLError(.badURL)
            }
        }
        let client = FootballDataAPIClient(session: session)

        let matches = try await client.fetchMatches(for: [.championsLeague])
        let seriesSummary = try XCTUnwrap(matches.first?.seriesSummary)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(seriesSummary.legNumber, 2)
        XCTAssertEqual(seriesSummary.legLabel, "2nd Leg")
        XCTAssertEqual(seriesSummary.totalLegs, 2)
        XCTAssertEqual(seriesSummary.homeAggregateScore, 2)
        XCTAssertEqual(seriesSummary.awayAggregateScore, 0)
    }
    func testFetchMatchesCoalescesAndReusesScoreboardPages() async throws {
        let startDate = Date().addingTimeInterval(24 * 60 * 60)
        let startDateText = ISO8601DateFormatter().string(from: startDate)
        let requestLock = NSLock()
        var scoreboardRequestCount = 0
        let session = makeMockSession { request in
            let url = try XCTUnwrap(request.url)
            guard url.path == "/apis/site/v2/sports/soccer/usa.1/scoreboard" else {
                XCTFail("Unexpected URL: \(url.absoluteString)")
                throw URLError(.badURL)
            }

            requestLock.lock()
            scoreboardRequestCount += 1
            requestLock.unlock()

            Thread.sleep(forTimeInterval: 0.05)
            return try self.jsonResponse(
                for: request,
                body: self.scoreboardBody(
                    leagueName: "MLS",
                    matchID: "shared-scoreboard-match",
                    startDateText: startDateText
                )
            )
        }
        let client = FootballDataAPIClient(session: session)

        async let firstFetch = client.fetchMatches(
            for: [.majorLeagueSoccer],
            enrichTeams: false
        )
        async let secondFetch = client.fetchMatches(
            for: [.majorLeagueSoccer],
            enrichTeams: false
        )
        let (firstMatches, secondMatches) = try await (firstFetch, secondFetch)
        let thirdMatches = try await client.fetchMatches(
            for: [.majorLeagueSoccer],
            enrichTeams: false
        )
        let calendar = Calendar(identifier: .gregorian)
        let dayStart = calendar.startOfDay(for: AlertCalendarClock.nowRoundedToSecond())
        let expectedStart = calendar.date(
            byAdding: .day,
            value: -FootballCompetitionPreset.majorLeagueSoccer.lookbackDays,
            to: dayStart
        ) ?? dayStart
        let expectedEnd = calendar.date(
            byAdding: .day,
            value: FootballCompetitionPreset.majorLeagueSoccer.lookaheadDays,
            to: dayStart
        ) ?? dayStart
        let expectedScoreboardRequestCount = 1 + FootballDataAPIClient.scoreboardDateRanges(
            start: expectedStart,
            end: expectedEnd,
            calendar: calendar
        ).count

        XCTAssertEqual(firstMatches.map(\.id), ["shared-scoreboard-match"])
        XCTAssertEqual(secondMatches.map(\.id), ["shared-scoreboard-match"])
        XCTAssertEqual(thirdMatches.map(\.id), ["shared-scoreboard-match"])
        XCTAssertEqual(scoreboardRequestCount, expectedScoreboardRequestCount)
    }
    func testFetchMatchesCanSkipTeamEnrichmentForLightweightLists() async throws {
        let startDate = Date().addingTimeInterval(24 * 60 * 60)
        let startDateText = ISO8601DateFormatter().string(from: startDate)
        let session = makeMockSession { request in
            let url = try XCTUnwrap(request.url)
            guard url.path == "/apis/site/v2/sports/soccer/usa.1/scoreboard" else {
                XCTFail("Unexpected team enrichment request: \(url.absoluteString)")
                throw URLError(.badURL)
            }

            return try self.jsonResponse(
                for: request,
                body: self.scoreboardBody(
                    leagueName: "MLS",
                    matchID: "lightweight-match",
                    startDateText: startDateText
                )
            )
        }
        let client = FootballDataAPIClient(session: session)

        let matches = try await client.fetchMatches(
            for: [.majorLeagueSoccer],
            enrichTeams: false
        )

        XCTAssertEqual(matches.count, 1)
        XCTAssertNil(matches.first?.locationText)
    }
    func testFetchMatchesSplitsDateRangeSoLaterFriendlyFixturesAreNotDropped() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let dayStart = calendar.startOfDay(for: AlertCalendarClock.nowRoundedToSecond())
        let targetDate = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 20, to: dayStart)?
                .addingTimeInterval(20 * 60 * 60)
        )
        let startDateText = ISO8601DateFormatter().string(from: targetDate)
        let queryDateFormatter = DateFormatter()
        queryDateFormatter.calendar = calendar
        queryDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        queryDateFormatter.timeZone = .autoupdatingCurrent
        queryDateFormatter.dateFormat = "yyyyMMdd"
        let targetDateText = queryDateFormatter.string(from: targetDate)
        let requestLock = NSLock()
        var requestedDateRanges: [String] = []

        let session = makeMockSession { request in
            let url = try XCTUnwrap(request.url)
            guard url.path == "/apis/site/v2/sports/soccer/fifa.friendly/scoreboard" else {
                XCTFail("Unexpected URL: \(url.absoluteString)")
                throw URLError(.badURL)
            }

            let dateRange = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "dates" })?
                .value

            if let dateRange {
                requestLock.lock()
                requestedDateRanges.append(dateRange)
                requestLock.unlock()
            }

            let dateRangeParts = dateRange?.split(separator: "-").map(String.init) ?? []
            let dateRangeContainsTarget = dateRangeParts.count == 2
                && dateRangeParts[0] <= targetDateText
                && targetDateText <= dateRangeParts[1]
            let body = dateRangeContainsTarget
                ? self.scoreboardBody(
                    leagueName: "FIFA Friendlies",
                    matchID: "costa-rica-england",
                    startDateText: startDateText
                )
                : [
                    "leagues": [["name": "FIFA Friendlies"]],
                    "events": [],
                ]

            return try self.jsonResponse(for: request, body: body)
        }
        let competition = FootballCompetitionPreset(
            slug: "fifa.friendly",
            title: "FIFA Friendlies",
            lookbackDays: 0,
            lookaheadDays: 45,
            category: .nationalTeams,
            region: .global
        )
        let client = FootballDataAPIClient(session: session)

        let matches = try await client.fetchMatches(
            for: [competition],
            enrichTeams: false
        )

        XCTAssertEqual(matches.map(\.id), ["costa-rica-england"])
        XCTAssertGreaterThan(requestedDateRanges.count, 1)
        XCTAssertTrue(
            requestedDateRanges.contains { dateRange in
                let parts = dateRange.split(separator: "-").map(String.init)
                return parts.count == 2
                    && parts[0] <= targetDateText
                    && targetDateText <= parts[1]
            }
        )
    }
    func testFetchMatchesPersistsTeamDetailsAcrossClientInstances() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = FootballTeamCacheStore(
            fileURL: tempDirectory.appendingPathComponent("football-team-cache.json")
        )
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let startDate = Date().addingTimeInterval(24 * 60 * 60)
        let startDateText = ISO8601DateFormatter().string(from: startDate)
        let requestLock = NSLock()
        var teamRequestCount = 0
        let session = makeMockSession { request in
            let url = try XCTUnwrap(request.url)

            switch url.path {
            case "/apis/site/v2/sports/soccer/usa.1/scoreboard":
                return try self.jsonResponse(
                    for: request,
                    body: self.scoreboardBody(
                        leagueName: "MLS",
                        matchID: "persisted-team-cache-match",
                        startDateText: startDateText
                    )
                )
            case "/v2/sports/soccer/teams/1845":
                requestLock.lock()
                teamRequestCount += 1
                requestLock.unlock()
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
                requestLock.lock()
                teamRequestCount += 1
                requestLock.unlock()
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

        let firstClient = FootballDataAPIClient(
            session: session,
            teamCacheStore: store
        )
        let firstMatches = try await firstClient.fetchMatches(for: [.majorLeagueSoccer])
        XCTAssertEqual(firstMatches.first?.locationText, "BMO Field, Toronto, Canada")

        let secondClient = FootballDataAPIClient(
            session: session,
            teamCacheStore: store
        )
        let secondMatches = try await secondClient.fetchMatches(for: [.majorLeagueSoccer])

        XCTAssertEqual(secondMatches.first?.locationText, "BMO Field, Toronto, Canada")
        XCTAssertEqual(teamRequestCount, 2)
    }

    private func scoreboardBody(
        leagueName: String,
        matchID: String,
        startDateText: String
    ) -> [String: Any] {
        [
            "leagues": [["name": leagueName]],
            "events": [[
                "id": matchID,
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
    }
}
