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
    }}
