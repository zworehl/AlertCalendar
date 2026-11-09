import Foundation
import XCTest
@testable import AlertCalendar

final class PandaScoreClientTests: IntegrationHTTPTestCase {
    private let instant = Date(timeIntervalSince1970: 1_798_761_600)

    private let players = #"{"id":7,"name":"Final","status":"finished","scheduled_at":"2026-11-01T10:00:00Z","begin_at":"2026-11-01T10:12:30.123Z","end_at":"2026-11-01T11:00:00Z","videogame":{"slug":"starcraft-2"},"league":{"id":11,"name":"Championship"},"opponents":[{"type":"Player","opponent":{"id":42,"name":"Alpha"}},{"type":"Player","opponent":{"id":84,"name":"Beta"}}],"results":[{"player_id":84,"score":3}],"streams_list":[{"raw_url":"https://www.twitch.tv/official","main":true,"official":true}],"number_of_games":5,"match_type":"best_of"}"#

    private func window() -> (Date, Date) {
        let date = ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z")!
        return (date.addingTimeInterval(-86_400), date.addingTimeInterval(86_400 * 2))
    }

    func testSC2PlayerScoresAndUTCFieldsDoNotInventMissingScores() async throws {
        let body = players
        let client = PandaScoreClient(session: session { request in
            self.reply(request, body: request.url!.path.hasSuffix("past") ? "[\(body)]" : "[]")
        })
        let dates = window()
        let result = try await client.load(game: .starCraft2, from: dates.0, to: dates.1, token: "private-test-token")
        let match = try XCTUnwrap(result.matches.first)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(match.id, "pandascore:starCraft2:7")
        XCTAssertEqual(match.status, .finished)
        XCTAssertEqual(match.opponents.map(\.type), [.player, .player])
        XCTAssertNil(match.score(for: match.opponents[0]))
        XCTAssertEqual(match.score(for: match.opponents[1]), 3)
        XCTAssertEqual(match.beginAt!.timeIntervalSince(match.scheduledAt!), 750.123, accuracy: 0.001)
        XCTAssertEqual(match.streamURL?.host, "www.twitch.tv")
    }

    func testTokenOnlyInAuthorizationAndCS2UsesLegacyRoute() async throws {
        let log = IntegrationRequestLog()
        let client = PandaScoreClient(session: session { request in
            log.record("all")
            XCTAssertEqual(request.url?.host, "api.pandascore.co")
            XCTAssertTrue(request.url!.path.hasPrefix("/csgo/matches/"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer private-test-token")
            XCTAssertFalse(request.url!.absoluteString.contains("private-test-token"))
            XCTAssertNil(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "token" })
            return self.reply(request, body: "[]")
        })
        let dates = window()
        _ = try await client.load(game: .counterStrike2, from: dates.0, to: dates.1, token: "private-test-token")
        XCTAssertEqual(log.count("all"), 3)
    }

    func testUntrustedPaginationCannotReceiveCredentialAndReturnsPartial() async throws {
        let log = IntegrationRequestLog()
        let client = PandaScoreClient(session: session { request in
            log.record(request.url!.host!)
            return self.reply(request, body: "[]", headers: request.url!.path.hasSuffix("upcoming") ? ["Link": "<https://attacker.test/collect>; rel=\"next\""] : [:])
        })
        let dates = window()
        let result = try await client.load(game: .leagueOfLegends, from: dates.0, to: dates.1, token: "private-test-token")
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.issues.first?.kind, .invalidPagination)
        XCTAssertEqual(log.count("attacker.test"), 0)
        XCTAssertEqual(log.count("api.pandascore.co"), 3)
    }

    func testPaginationLimitIsExplicitAndCommaInsideDateRangeIsSupported() async throws {
        let log = IntegrationRequestLog()
        let client = PandaScoreClient(session: session { request in
            log.record("all")
            let next = "https://api.pandascore.co\(request.url!.path)?page=2&range%5Bscheduled_at%5D=2026-10-31,2026-11-03"
            return self.reply(request, body: "[]", headers: ["Link": "<\(next)>; rel=\"next\""])
        }, maximumPages: 1)
        let dates = window()
        let result = try await client.load(game: .rocketLeague, from: dates.0, to: dates.1, token: "private-test-token")
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.issues.map(\.kind), [.paginationLimit, .paginationLimit, .paginationLimit])
        XCTAssertEqual(log.count("all"), 3)
    }

    func testPartiallyInvalidPayloadPreservesValidFixtureAndReportsPartial() async throws {
        let body = players
        let client = PandaScoreClient(session: session { request in
            self.reply(request, body: request.url!.path.hasSuffix("past") ? "[\(body),{\"id\":0,\"name\":\"bad\",\"status\":\"finished\"}]" : "[]")
        })
        let dates = window()
        let result = try await client.load(game: .starCraft2, from: dates.0, to: dates.1, token: "private-test-token")
        XCTAssertEqual(result.matches.count, 1)
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.issues.first?.kind, .invalidPayload)
    }

    func testUnauthorizedAndPlanDeniedBodiesNeverBecomeErrorsOrRepeatedProbes() async throws {
        let dates = window()
        for status in [401, 403] {
            let log = IntegrationRequestLog()
            let client = PandaScoreClient(session: session { request in
                log.record("all")
                return self.reply(request, status: status, body: "private-test-token sensitive response")
            })
            do {
                _ = try await client.load(game: .leagueOfLegends, from: dates.0, to: dates.1, token: "private-test-token")
                XCTFail("Expected sanitized failure")
            } catch let error as PandaScoreError {
                XCTAssertEqual(error, status == 401 ? .unauthorized : .unavailable)
                XCTAssertFalse(String(describing: error).contains("private-test-token"))
            }
            XCTAssertEqual(log.count("all"), 1)
        }
    }

    func testRateLimitSurvivesAnotherManualLoadAndServerRetryAfter() async throws {
        let log = IntegrationRequestLog()
        let instant = self.instant
        let client = PandaScoreClient(session: session { request in
            log.record("all")
            return self.reply(request, status: 429, headers: ["Retry-After": "600"])
        }, now: { instant })
        let dates = window()
        for _ in 0..<2 {
            do {
                _ = try await client.load(game: .leagueOfLegends, from: dates.0, to: dates.1, token: "private-test-token")
                XCTFail("Expected rate limit")
            } catch let error as PandaScoreError {
                switch error {
                case .rateLimited(let until): XCTAssertEqual(until, instant.addingTimeInterval(600))
                case .retryDeferred(let status, let until):
                    XCTAssertEqual(status, 429)
                    XCTAssertEqual(until, instant.addingTimeInterval(600))
                default: XCTFail("Unexpected \(error)")
                }
            }
        }
        XCTAssertEqual(log.count("all"), 1)
    }

    func testHourlyBudgetIsBoundedAcrossGames() async throws {
        let log = IntegrationRequestLog()
        let instant = self.instant
        let client = PandaScoreClient(session: session { request in
            log.record("all")
            return self.reply(request, body: "[]")
        }, hourlyRequestLimit: 1, now: { instant })
        let dates = window()
        let result = try await client.load(game: .leagueOfLegends, from: dates.0, to: dates.1, token: "private-test-token")
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.issues.first?.kind, .requestBudget)
        do {
            _ = try await client.load(game: .counterStrike2, from: dates.0, to: dates.1, token: "private-test-token")
            XCTFail("Expected shared client budget")
        } catch let error as PandaScoreError { XCTAssertEqual(error, .requestBudget(until: instant.addingTimeInterval(3_600))) }
        XCTAssertEqual(log.count("all"), 1)
    }

    func testMissingTrackedMatchUsesFreeGenericDetailAndRetainsPostponedDate() async throws {
        let log = IntegrationRequestLog()
        let client = PandaScoreClient(session: session { request in
            log.record(request.url!.path)
            return self.reply(request, body: request.url!.path == "/matches/7" ? #"{"id":7,"name":"Final","status":"postponed","scheduled_at":"2020-01-01T00:00:00Z"}"# : "[]")
        })
        let dates = window()
        let result = try await client.load(game: .starCraft2, from: dates.0, to: dates.1, token: "private-test-token", trackedIDs: [7])
        XCTAssertEqual(result.matches.first?.status, .postponed)
        XCTAssertNotNil(result.matches.first?.scheduledAt)
        XCTAssertEqual(log.count("/matches/7"), 1)
        XCTAssertTrue(result.isComplete)
    }

    func testCancellationBeforeLoadMakesNoRequest() async throws {
        let log = IntegrationRequestLog()
        let client = PandaScoreClient(session: session { request in log.record("all"); return self.reply(request, body: "[]") })
        let dates = window()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.load(game: .leagueOfLegends, from: dates.0, to: dates.1, token: "private-test-token")
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        XCTAssertEqual(log.count("all"), 0)
    }

    func testMaximumNormalizedSettingsWindowIsAcceptedWithoutIncreasingBudget() async throws {
        var settings = EsportsSettings()
        settings.lookbackDays = 365
        settings.lookaheadDays = 180
        let normalized = settings.normalized
        let log = IntegrationRequestLog()
        let client = PandaScoreClient(session: session { request in log.record("all"); return self.reply(request, body: "[]") })
        let result = try await client.load(game: .leagueOfLegends,
            from: instant.addingTimeInterval(-Double(normalized.lookbackDays) * 86_400),
            to: instant.addingTimeInterval(Double(normalized.lookaheadDays) * 86_400), token: "private-test-token")
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(log.count("all"), 3)
    }

    func testUpcomingTBDAndExplicitPostponedMatchesRemainVisibleWithoutInventingDate() async throws {
        let client = PandaScoreClient(session: session { request in
            self.reply(request, body: request.url!.path.hasSuffix("upcoming")
                ? #"[{"id":8,"name":"TBD final","status":"not_started","scheduled_at":null},{"id":9,"name":"Postponed final","status":"postponed","scheduled_at":"2020-01-01T00:00:00Z"}]"# : "[]")
        })
        let dates = window()
        let result = try await client.load(game: .leagueOfLegends, from: dates.0, to: dates.1, token: "private-test-token")
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.matches.count, 2)
        XCTAssertNil(result.matches.first { $0.providerID == 8 }?.scheduledAt)
        XCTAssertEqual(result.matches.first { $0.providerID == 9 }?.status, .postponed)
    }
}
