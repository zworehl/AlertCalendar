import Foundation
import XCTest
@testable import AlertCalendar

final class FootballScoreFreshnessTests: FootballDataAPIClientTestCase {
    func testForcedStatusRefreshUpdatesScoreDespiteFreshSummaryCache() async throws {
        let lock = NSLock()
        var requestCount = 0
        let session = makeMockSession { request in
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            let count = lock.withLock { requestCount += 1; return requestCount }
            return try self.jsonResponse(for: request, body: self.summaryBody(homeScore: count == 1 ? "0" : "3"))
        }
        let client = FootballDataAPIClient(session: session)
        let match = FootballTestData.friendlyMatch(
            id: "freshness-match", startDate: Date().addingTimeInterval(-30 * 60),
            statusState: .inProgress, statusText: "30'", homeScore: "0", awayScore: "0"
        )

        let initial = await client.refreshStatusesIfNeeded(for: [match])
        let cached = await client.refreshStatusesIfNeeded(for: initial)
        XCTAssertEqual(cached.first?.homeScore, "0")
        XCTAssertEqual(lock.withLock { requestCount }, 1)

        let refreshed = await client.refreshStatusesIfNeeded(for: cached, forceRefresh: true)
        XCTAssertEqual(refreshed.first?.homeScore, "3")
        XCTAssertEqual(lock.withLock { requestCount }, 2)
    }

    func testScoreboardNetworkFetchBypassesSystemHTTPCache() async throws {
        let session = makeMockSession { request in
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            return try self.jsonResponse(for: request, body: ["events": []])
        }
        let client = FootballDataAPIClient(session: session)
        let result = try await client.fetchFixtureLoadResult(
            for: [.fifaFriendlies], enrichTeams: false, forceRefresh: true
        )
        XCTAssertTrue(result.failures.isEmpty)
    }

    private func summaryBody(homeScore: String) -> [String: Any] {
        ["header": ["competitions": [[
            "status": ["type": ["state": "in", "shortDetail": "30'"]],
            "competitors": [
                ["homeAway": "home", "score": homeScore, "team": ["id": "1", "displayName": "Home"]],
                ["homeAway": "away", "score": "0", "team": ["id": "2", "displayName": "Away"]]
            ]
        ]]]]
    }
}
