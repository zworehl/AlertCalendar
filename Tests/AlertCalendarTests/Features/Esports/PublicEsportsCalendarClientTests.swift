import Foundation
import XCTest
@testable import AlertCalendar

final class PublicEsportsCalendarClientTests: IntegrationHTTPTestCase {
    private typealias Feed = PublicEsportsCalendarTestData

    func testEachSupportedGameUsesAnonymousPublicGETAndBoundedTimeout() async throws {
        let body = try Feed.fixture(), log = IntegrationRequestLog()
        let client = PublicEsportsCalendarClient(session: session { request in
            log.record("all")
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.host, "www.esport-calendar.com")
            XCTAssertEqual(request.url?.path, "/calendar.ics")
            XCTAssertNil(request.url?.user)
            XCTAssertNil(request.url?.password)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.timeoutInterval, 25)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertNil(request.value(forHTTPHeaderField: "X-API-Key"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/calendar")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertEqual(query.map(\.name), ["games"])
            return self.response(request, data: body)
        }, now: { Feed.fetchedAt })
        for (game, slug) in [(EsportsGame.leagueOfLegends, "league-of-legends"), (.counterStrike2, "cs-go"), (.starCraft2, "starcraft-2"), (.rocketLeague, "rl")] {
            let result = try await client.load(game: game, from: Feed.from, to: Feed.to)
            XCTAssertEqual(PublicEsportsCalendarClient.slug(for: game), slug)
            XCTAssertTrue(result.isComplete)
            XCTAssertTrue(result.matches.allSatisfy { $0.game == game })
            XCTAssertEqual(result.fetchedAt, Feed.fetchedAt)
        }
        XCTAssertEqual(log.count("all"), 4)
    }

    func testValidEmptyGameFeedIsCompleteWithoutInventingFixtures() async throws {
        let body = try Feed.fixture()
        let client = PublicEsportsCalendarClient(session: session { self.response($0, data: body) })
        let result = try await client.load(game: .rocketLeague, from: Feed.from, to: Feed.to)
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.matches.isEmpty)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testMalformedPerGameEventReturnsKnownMatchesWithExplicitPartialIssue() async throws {
        let invalid = Feed.event(id: 9).replacingOccurrences(of: "pandascore-9@esports-calendar.local", with: "unverified-source")
        let body = Feed.calendar([Feed.event(), invalid])
        let client = PublicEsportsCalendarClient(session: session { self.response($0, data: body) })
        let result = try await client.load(game: .leagueOfLegends, from: Feed.from, to: Feed.to)
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.matches.map(\.providerID), [1711021])
        XCTAssertEqual(result.issues.map(\.kind), [.invalidPayload])
    }

    func testTrackedFixtureOutsideBrowseWindowIsStillReturnedForManagedUpdates() async throws {
        let body = Feed.calendar([Feed.event(id: 1, start: "20260101T190000Z", end: "20260101T210000Z"), Feed.event(id: 2)])
        let client = PublicEsportsCalendarClient(session: session { self.response($0, data: body) })
        let result = try await client.load(game: .leagueOfLegends, from: Feed.from, to: Feed.to, trackedIDs: [1])
        XCTAssertEqual(Set(result.matches.map(\.providerID)), [1, 2])
    }

    func testFinalResponseMustRemainOnExactPublicFeedRouteAndSelectedGame() async throws {
        let body = Feed.calendar([Feed.event()])
        let invalid = [
            "https://attacker.test/calendar.ics?games=league-of-legends",
            "https://www.esport-calendar.com.attacker.test/calendar.ics?games=league-of-legends",
            "http://www.esport-calendar.com/calendar.ics?games=league-of-legends",
            "https://user:password@www.esport-calendar.com/calendar.ics?games=league-of-legends",
            "https://www.esport-calendar.com:444/calendar.ics?games=league-of-legends",
            "https://www.esport-calendar.com/other.ics?games=league-of-legends",
            "https://www.esport-calendar.com/calendar.ics?games=cs-go",
            "https://www.esport-calendar.com/calendar.ics?games=league-of-legends&key=unexpected",
            "https://www.esport-calendar.com/calendar.ics?games=league-of-legends#fragment"
        ]
        for finalURL in invalid {
            let client = PublicEsportsCalendarClient(session: session { request in
                self.response(request, data: body, finalURL: URL(string: finalURL)!)
            })
            do {
                _ = try await client.load(game: .leagueOfLegends, from: Feed.from, to: Feed.to)
                XCTFail("Untrusted final response URL must fail: \(finalURL)")
            } catch { XCTAssertEqual(error as? EsportsFeedError, .invalidResponse, finalURL) }
        }
    }

    func testApexCanonicalRedirectRetainsTrustedFeedAndGame() async throws {
        let body = Feed.calendar([Feed.event()])
        let client = PublicEsportsCalendarClient(session: session { request in
            self.response(request, data: body, finalURL: URL(string: "https://esport-calendar.com/calendar.ics?games=league-of-legends")!)
        })
        let result = try await client.load(game: .leagueOfLegends, from: Feed.from, to: Feed.to)
        XCTAssertEqual(result.matches.count, 1)
    }

    func testHTTPFailuresAndMalformedBodiesNeverBecomeSuccessfulEmptySchedules() async throws {
        for status in [401, 403, 500] {
            let client = PublicEsportsCalendarClient(session: session { request in
                self.reply(request, status: status, body: "sensitive upstream diagnostic must not be surfaced")
            })
            do {
                _ = try await client.load(game: .leagueOfLegends, from: Feed.from, to: Feed.to)
                XCTFail("Expected failure")
            } catch {
                XCTAssertEqual(error as? EsportsFeedError, status == 500 ? .unexpectedStatus(500) : .unavailable)
                XCTAssertFalse(String(describing: error).contains("sensitive upstream"))
            }
        }
        for body in [Data("<html>maintenance</html>".utf8), Data([0xFF]), Data(repeating: 0x61, count: 5_000_001)] {
            let client = PublicEsportsCalendarClient(session: session { self.response($0, data: body) })
            do {
                _ = try await client.load(game: .leagueOfLegends, from: Feed.from, to: Feed.to)
                XCTFail("Expected invalid payload")
            } catch { XCTAssertEqual(error as? EsportsFeedError, .invalidPayload) }
        }
    }

    func testServerRetryAfterSurvivesManualRetryWithoutAnotherRequest() async throws {
        let log = IntegrationRequestLog()
        let client = PublicEsportsCalendarClient(session: session { request in
            log.record("all")
            return self.reply(request, status: 429, headers: ["Retry-After": "600"])
        }, now: { Feed.fetchedAt })
        for attempt in 0..<2 {
            do {
                _ = try await client.load(game: .leagueOfLegends, from: Feed.from, to: Feed.to)
                XCTFail("Expected rate limiting")
            } catch let error as EsportsFeedError {
                switch error {
                case .rateLimited(let until):
                    XCTAssertEqual(attempt, 0)
                    XCTAssertEqual(until, Feed.fetchedAt.addingTimeInterval(600))
                case .retryDeferred(let status, let until):
                    XCTAssertEqual(attempt, 1)
                    XCTAssertEqual(status, 429)
                    XCTAssertEqual(until, Feed.fetchedAt.addingTimeInterval(600))
                default: XCTFail("Unexpected error: \(error)")
                }
            }
        }
        XCTAssertEqual(log.count("all"), 1)
    }

    func testHourlyBudgetIsSharedAcrossGames() async throws {
        let log = IntegrationRequestLog()
        let client = PublicEsportsCalendarClient(session: session { request in
            log.record("all"); return self.response(request, data: Feed.calendar([]))
        }, hourlyRequestLimit: 1, now: { Feed.fetchedAt })
        _ = try await client.load(game: .leagueOfLegends, from: Feed.from, to: Feed.to)
        do {
            _ = try await client.load(game: .counterStrike2, from: Feed.from, to: Feed.to)
            XCTFail("Expected shared request budget")
        } catch { XCTAssertEqual(error as? EsportsFeedError, .requestBudget(until: Feed.fetchedAt.addingTimeInterval(3_600))) }
        XCTAssertEqual(log.count("all"), 1)
    }

    func testUnsupportedGamesInvalidWindowsAndCancellationDoNotSendRequests() async throws {
        let log = IntegrationRequestLog()
        let client = PublicEsportsCalendarClient(session: session { request in
            log.record("all"); return self.response(request, data: Feed.calendar([]))
        })
        do {
            _ = try await client.load(game: .granTurismo7, from: Feed.from, to: Feed.to)
            XCTFail("Expected unsupported game")
        } catch { XCTAssertEqual(error as? EsportsFeedError, .unsupportedGame) }
        for end in [Feed.from, Feed.from.addingTimeInterval(551 * 86_400)] {
            do {
                _ = try await client.load(game: .leagueOfLegends, from: Feed.from, to: end)
                XCTFail("Expected invalid window")
            } catch { XCTAssertEqual(error as? EsportsFeedError, .invalidWindow) }
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.load(game: .leagueOfLegends, from: Feed.from, to: Feed.to)
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(log.count("all"), 0)
    }

    func testMaximumSettingsWindowIsAcceptedAndNetworkTimeoutIsSanitized() async throws {
        let log = IntegrationRequestLog()
        let client = PublicEsportsCalendarClient(session: session { request in
            log.record("all"); throw URLError(.timedOut)
        })
        do {
            _ = try await client.load(game: .leagueOfLegends, from: Feed.fetchedAt.addingTimeInterval(-365 * 86_400),
                                      to: Feed.fetchedAt.addingTimeInterval(180 * 86_400))
            XCTFail("Expected network failure")
        } catch { XCTAssertEqual(error as? EsportsFeedError, .networkUnavailable) }
        XCTAssertEqual(log.count("all"), 1, "The normalized 545-day settings range must reach the transport")
    }

    private func response(_ request: URLRequest, data: Data, finalURL: URL? = nil) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: finalURL ?? request.url!, statusCode: 200, httpVersion: nil,
                         headerFields: ["Content-Type": "text/calendar; charset=utf-8"])!, data)
    }
}
