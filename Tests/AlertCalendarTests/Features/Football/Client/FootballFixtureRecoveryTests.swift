import Foundation
import XCTest
@testable import AlertCalendar

final class FootballFixtureRecoveryTests: FootballDataAPIClientTestCase {
    private let firstDay = Calendar.current.startOfDay(for: Date())
    private var secondDay: Date { Calendar.current.date(byAdding: .day, value: 1, to: firstDay)! }
    private var ranges: [String: [FootballScoreboardDateRange]] {
        ["fifa.friendly": [
            FootballScoreboardDateRange(start: firstDay, end: firstDay),
            FootballScoreboardDateRange(start: secondDay, end: secondDay)
        ]]
    }

    func testPartialLoadKeepsSuccessfulPageAndRestoresOnlyFailedRangeFromCache() async throws {
        let failingURL = FootballDataAPIClient.scoreboardURL(slug: "fifa.friendly", dateRange: (secondDay, secondDay))
        let session = makeMockSession { request in
            if request.url == failingURL { throw URLError(.notConnectedToInternet) }
            return try self.jsonResponse(for: request, body: self.body(id: "fresh", date: self.firstDay))
        }
        let client = FootballDataAPIClient(session: session)
        let result = try await client.fetchFixtureLoadResult(
            for: [.fifaFriendlies], dateRangesByCompetitionSlug: ranges, enrichTeams: false
        )
        XCTAssertEqual(result.matches.map(\.id), ["fresh"])
        XCTAssertEqual(result.availablePageCount, 1)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertNotNil(result.warning)
        let cached = [
            FootballTestData.friendlyMatch(id: "cached-missing-range", startDate: secondDay, statusState: .scheduled),
            FootballTestData.friendlyMatch(id: "removed-from-successful-range", startDate: firstDay, statusState: .scheduled)
        ]
        XCTAssertEqual(result.restoringCachedMatches(cached).map(\.id), ["fresh", "cached-missing-range"])
        XCTAssertNoThrow(try result.requireAvailableMatches())
    }

    func testAllFailedRangesAreNotReportedAsAnEmptySuccessfulSeason() async throws {
        let client = FootballDataAPIClient(session: makeMockSession { _ in throw URLError(.notConnectedToInternet) })
        let result = try await client.fetchFixtureLoadResult(
            for: [.fifaFriendlies], dateRangesByCompetitionSlug: ranges, enrichTeams: false
        )
        XCTAssertEqual(result.availablePageCount, 0)
        XCTAssertEqual(result.failures.count, 2)
        XCTAssertThrowsError(try result.requireAvailableMatches())
    }

    func testCachedPageRemainsMarkedStaleUntilSuccessfulNetworkRefresh() async throws {
        let lock = NSLock()
        var offline = false
        var count = 0
        let session = makeMockSession { request in
            let shouldFail = lock.withLock { count += 1; return offline }
            if shouldFail { throw URLError(.notConnectedToInternet) }
            return try self.jsonResponse(for: request, body: self.body(id: "match", date: self.firstDay))
        }
        let client = FootballDataAPIClient(session: session)
        let oneRange = ["fifa.friendly": [ranges["fifa.friendly"]!.first!]]
        _ = try await client.fetchFixtureLoadResult(for: [.fifaFriendlies], dateRangesByCompetitionSlug: oneRange, enrichTeams: false)
        lock.withLock { offline = true }
        let stale = try await client.fetchFixtureLoadResult(for: [.fifaFriendlies], dateRangesByCompetitionSlug: oneRange, enrichTeams: false, forceRefresh: true)
        XCTAssertEqual(stale.matches.count, 1)
        XCTAssertNotNil(stale.warning)
        let backedOff = try await client.fetchFixtureLoadResult(for: [.fifaFriendlies], dateRangesByCompetitionSlug: oneRange, enrichTeams: false)
        XCTAssertNotNil(backedOff.warning)
        XCTAssertEqual(lock.withLock { count }, 2)
        lock.withLock { offline = false }
        let recovered = try await client.fetchFixtureLoadResult(for: [.fifaFriendlies], dateRangesByCompetitionSlug: oneRange, enrichTeams: false, forceRefresh: true)
        XCTAssertNil(recovered.warning)
    }

    func testTransientServerFailureRetriesAndCancellationDoesNotBecomeAnOutage() async throws {
        let lock = NSLock()
        var count = 0
        let session = makeMockSession { request in
            let attempt = lock.withLock { count += 1; return count }
            if attempt == 1 {
                return (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data())
            }
            return try self.jsonResponse(for: request, body: self.body(id: "recovered", date: self.firstDay))
        }
        let client = FootballDataAPIClient(session: session)
        let result = try await client.fetchFixtureLoadResult(
            for: [.fifaFriendlies], dateRangesByCompetitionSlug: ["fifa.friendly": [ranges["fifa.friendly"]!.first!]], enrichTeams: false
        )
        XCTAssertNil(result.warning)
        XCTAssertEqual(result.matches.map(\.id), ["recovered"])
        XCTAssertEqual(lock.withLock { count }, 2)
        XCTAssertFalse(FootballDataAPIClient.isRetryableFixtureError(URLError(.cancelled)))
        XCTAssertFalse(FootballDataAPIClient.isRetryableFixtureError(FootballDataAPIClient.ClientError.unsuccessfulResponse(statusCode: 404)))
    }

    func testRateLimitRespectsRetryAfterEvenForManualRetry() async throws {
        let lock = NSLock()
        var count = 0
        let session = makeMockSession { request in
            lock.withLock { count += 1 }
            return (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "600"])!, Data())
        }
        let client = FootballDataAPIClient(session: session)
        let oneRange = ["fifa.friendly": [ranges["fifa.friendly"]!.first!]]
        let first = try await client.fetchFixtureLoadResult(for: [.fifaFriendlies], dateRangesByCompetitionSlug: oneRange, enrichTeams: false, forceRefresh: true)
        let second = try await client.fetchFixtureLoadResult(for: [.fifaFriendlies], dateRangesByCompetitionSlug: oneRange, enrichTeams: false, forceRefresh: true)
        XCTAssertEqual(lock.withLock { count }, 1)
        XCTAssertTrue(second.warning?.contains("429") == true)
        XCTAssertEqual(first.failures.first?.attemptedAt, second.failures.first?.attemptedAt)
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(FootballDataAPIClient.rateLimitRetryDate(header: "600", now: now), now.addingTimeInterval(600))
        XCTAssertEqual(FootballDataAPIClient.rateLimitRetryDate(header: "Thu, 01 Jan 1970 00:10:00 GMT", now: now), now.addingTimeInterval(600))
    }

    func testInvalidSuccessPayloadIsReportedAsFailure() async throws {
        let client = FootballDataAPIClient(session: makeMockSession { request in
            try self.jsonResponse(for: request, body: ["error": "unavailable"])
        })
        let result = try await client.fetchFixtureLoadResult(for: [.fifaFriendlies], dateRangesByCompetitionSlug: ranges, enrichTeams: false)
        XCTAssertEqual(result.availablePageCount, 0)
        XCTAssertEqual(result.failures.count, 2)
    }

    func testRejectedRangeFallsBackToPublishedMatchDaysAndRetainsDayFailures() async throws {
        let calendar = Calendar.current
        let rangeEnd = calendar.date(byAdding: .day, value: 13, to: firstDay)!
        let seasonEnd = calendar.date(byAdding: .day, value: 365, to: firstDay)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let league: [String: Any] = [
            "calendarType": "day", "calendarIsWhitelist": true,
            "calendarStartDate": formatter.string(from: firstDay),
            "calendarEndDate": formatter.string(from: seasonEnd),
            "calendar": [formatter.string(from: firstDay), formatter.string(from: secondDay)]
        ]
        let secondURL = FootballDataAPIClient.scoreboardURL(slug: "fifa.friendly", dateRange: (secondDay, secondDay))
        let lock = NSLock()
        var requested: [String] = []
        let session = makeMockSession { request in
            let dates = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
            lock.withLock { requested.append(dates ?? "calendar") }
            if dates?.contains("-") == true {
                return (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, Data())
            }
            if dates == nil { return try self.jsonResponse(for: request, body: ["leagues": [league], "events": []]) }
            if request.url == secondURL { throw URLError(.notConnectedToInternet) }
            return try self.jsonResponse(for: request, body: self.body(id: "daily-match", date: self.firstDay))
        }
        let client = FootballDataAPIClient(session: session)
        let requestedRanges = ["fifa.friendly": [FootballScoreboardDateRange(start: firstDay, end: rangeEnd)]]
        let result = try await client.fetchFixtureLoadResult(for: [.fifaFriendlies], dateRangesByCompetitionSlug: requestedRanges, enrichTeams: false)
        XCTAssertEqual(result.matches.map(\.id), ["daily-match"])
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures.first?.range.start, secondDay)
        XCTAssertFalse(result.warning?.contains("400") == true)
        XCTAssertEqual(lock.withLock { requested.count }, 4)
        _ = try await client.fetchFixtureLoadResult(for: [.fifaFriendlies], dateRangesByCompetitionSlug: requestedRanges, enrichTeams: false)
        XCTAssertEqual(lock.withLock { requested.count }, 4, "Use cached calendar/pages and respect failed-day backoff")
    }

    func testSingleDayQueriesAndCacheFreshness() throws {
        let today = FootballDataAPIClient.scoreboardURL(slug: "eng.1", dateRange: (firstDay, firstDay))!
        let distant = Calendar.current.date(byAdding: .day, value: 10, to: firstDay)!
        let future = FootballDataAPIClient.scoreboardURL(slug: "eng.1", dateRange: (distant, distant))!
        let dates = URLComponents(url: today, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        XCTAssertEqual(dates?.count, 8)
        XCTAssertEqual(FootballDataAPIClient.scoreboardPageCacheTTL(for: today, now: firstDay), 300)
        XCTAssertEqual(FootballDataAPIClient.scoreboardPageCacheTTL(for: future, now: firstDay), 3_600)
        let published = FootballScoreboardCalendar(root: ["leagues": [[
            "calendarType": "day", "calendarIsWhitelist": true, "calendarStartDate": "2026-08-01",
            "calendarEndDate": "2027-06-01", "calendar": []
        ]]])!
        let outside = Calendar.current.date(from: DateComponents(year: 2027, month: 8, day: 1))!
        XCTAssertTrue(published.includesOrDoesNotCover(outside, calendar: .current))
    }

    func testCancellationPropagatesWithoutReportingFailedRanges() async {
        let client = FootballDataAPIClient(session: makeMockSession { _ in throw URLError(.cancelled) })
        do {
            _ = try await client.fetchFixtureLoadResult(
                for: [.fifaFriendlies], dateRangesByCompetitionSlug: ranges, enrichTeams: false, healthScope: "cancellation-test"
            )
            XCTFail("Cancellation must propagate")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
        }
        let issues = await DataRefreshHealth.shared.snapshot()
        XCTAssertFalse(issues.contains { $0.id.hasPrefix("football.cancellation-test.") })
    }

    private func body(id: String, date: Date) -> [String: Any] {
        ["events": [["id": id, "date": ISO8601DateFormatter().string(from: date), "competitions": [[
            "status": ["type": ["state": "pre", "shortDetail": "Scheduled"]],
            "competitors": [
                ["homeAway": "home", "score": "0", "team": ["id": "1", "displayName": "Home"]],
                ["homeAway": "away", "score": "0", "team": ["id": "2", "displayName": "Away"]]
            ]
        ]]]]]
    }
}
