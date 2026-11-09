import Foundation
import XCTest
@testable import AlertCalendar

final class FootballMonthlyScoreboardTests: FootballDataAPIClientTestCase {
    func testMonthlyFallbackAcceptsOver100EventsAndCoalescesForcedOverlappingRanges() async throws {
        let lock = NSLock()
        var monthlyRequests = 0
        let start = day(2026, 3, 10)
        let events = (0..<130).map { event(id: "match-\($0)", date: day(2026, 3, 15)) }
            + [event(id: "outside", date: day(2026, 3, 1))]
        let client = FootballDataAPIClient(session: makeMockSession { request in
            let dates = self.dates(request)
            if dates?.contains("-") == true { return self.response(request, status: 400) }
            XCTAssertEqual(dates, "202603")
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "limit" })?.value, "1000")
            lock.withLock { monthlyRequests += 1 }
            return try self.jsonResponse(for: request, body: ["events": events])
        })
        let result = try await client.fetchFixtureLoadResult(
            for: [.fifaFriendlies], dateRangesByCompetitionSlug: ["fifa.friendly": [
                FootballScoreboardDateRange(start: start, end: day(2026, 3, 19)),
                FootballScoreboardDateRange(start: day(2026, 3, 14), end: day(2026, 3, 25))
            ]], enrichTeams: false, forceRefresh: true
        )
        XCTAssertNil(result.warning)
        XCTAssertEqual(result.matches.count, 130)
        XCTAssertFalse(result.matches.contains { $0.id == "outside" })
        XCTAssertEqual(lock.withLock { monthlyRequests }, 1)
    }

    func testNeighboringMonthCoversProviderTimezoneBoundaryAndFiltersExactWindow() async throws {
        let lock = NSLock()
        var months: [String] = []
        let start = day(2026, 4, 1)
        let client = FootballDataAPIClient(session: makeMockSession { request in
            let dates = self.dates(request)!
            if dates.contains("-") { return self.response(request, status: 400) }
            lock.withLock { months.append(dates) }
            let events = dates == "202603"
                ? [self.event(id: "boundary", date: start.addingTimeInterval(30 * 60)),
                   self.event(id: "too-early", date: start.addingTimeInterval(-60))]
                : [self.event(id: "april", date: self.day(2026, 4, 2)),
                   self.event(id: "too-late", date: self.day(2026, 4, 4))]
            return try self.jsonResponse(for: request, body: ["events": events])
        })
        let result = try await load(client, start: start, end: day(2026, 4, 3))
        XCTAssertNil(result.warning)
        XCTAssertEqual(Set(result.matches.map(\.id)), ["boundary", "april"])
        XCTAssertEqual(Set(lock.withLock { months }), ["202603", "202604"])
    }

    func testPotentiallyTruncatedMonthFallsBackEvenWhenAnOlderMonthIsCached() async throws {
        let lock = NSLock()
        var truncate = false
        var monthlyRequests = 0
        let start = day(2026, 4, 14)
        let matchDay = day(2026, 4, 15)
        let client = FootballDataAPIClient(session: makeMockSession { request in
            let dates = self.dates(request)
            if dates?.contains("-") == true { return self.response(request, status: 400) }
            if dates?.count == 6 {
                let shouldTruncate = lock.withLock { monthlyRequests += 1; return truncate }
                let events: [[String: Any]] = shouldTruncate
                    ? Array(repeating: [:], count: FootballDataAPIClient.monthlyScoreboardLimit)
                    : [self.event(id: "old-month", date: matchDay)]
                return try self.jsonResponse(for: request, body: ["events": events])
            }
            if dates == nil {
                return try self.jsonResponse(for: request, body: ["events": [], "leagues": [[
                    "calendarType": "day", "calendarIsWhitelist": true,
                    "calendarStartDate": "2026-01-01", "calendarEndDate": "2027-01-01",
                    "calendar": ["2026-04-15"]
                ]]])
            }
            XCTAssertEqual(dates, "20260415")
            return try self.jsonResponse(for: request, body: ["events": [self.event(id: "fresh-day", date: matchDay)]])
        })
        let initial = try await load(client, start: start, end: matchDay)
        XCTAssertEqual(initial.matches.map(\.id), ["old-month"])
        lock.withLock { truncate = true }
        let refreshed = try await load(client, start: start, end: matchDay, force: true)
        XCTAssertNil(refreshed.warning)
        XCTAssertEqual(refreshed.matches.map(\.id), ["fresh-day"])
        _ = try await load(client, start: start, end: matchDay)
        XCTAssertEqual(lock.withLock { monthlyRequests }, 2, "A capped month should use cached daily fallback")
    }

    func testDeniedMonthRemainsFailedWithoutDailyRequestFanout() async throws {
        let lock = NSLock()
        var requests = 0
        let client = FootballDataAPIClient(session: makeMockSession { request in
            lock.withLock { requests += 1 }
            return self.response(request, status: self.dates(request)?.contains("-") == true ? 400 : 403)
        })
        let result = try await load(client, start: day(2026, 4, 14), end: day(2026, 4, 15))
        XCTAssertEqual(result.availablePageCount, 0)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(result.warning?.contains("403") == true)
        XCTAssertEqual(lock.withLock { requests }, 2)
    }

    func testMonthlyCacheTTLUsesTheMonthContainingToday() throws {
        let now = day(2026, 11, 8)
        let current = try XCTUnwrap(FootballDataAPIClient.monthlyScoreboardURL(slug: "eng.1", month: now))
        let distant = try XCTUnwrap(FootballDataAPIClient.monthlyScoreboardURL(slug: "eng.1", month: day(2026, 12, 1)))
        XCTAssertEqual(FootballDataAPIClient.scoreboardPageCacheTTL(for: current, now: now), 300)
        XCTAssertEqual(FootballDataAPIClient.scoreboardPageCacheTTL(for: distant, now: now), 3_600)
    }

    private func load(_ client: FootballDataAPIClient, start: Date, end: Date, force: Bool = false) async throws -> FootballFixtureLoadResult {
        try await client.fetchFixtureLoadResult(
            for: [.fifaFriendlies], dateRangesByCompetitionSlug: ["fifa.friendly": [FootballScoreboardDateRange(start: start, end: end)]],
            enrichTeams: false, forceRefresh: force
        )
    }
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
    private func dates(_ request: URLRequest) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "dates" })?.value
    }
    private func response(_ request: URLRequest, status: Int) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data())
    }
    private func event(id: String, date: Date) -> [String: Any] {
        ["id": id, "date": ISO8601DateFormatter().string(from: date), "competitions": [[
            "status": ["type": ["state": "pre", "shortDetail": "Scheduled"]],
            "competitors": [
                ["homeAway": "home", "score": "0", "team": ["id": "1", "displayName": "Home"]],
                ["homeAway": "away", "score": "0", "team": ["id": "2", "displayName": "Away"]]
            ]
        ]]]
    }
}
