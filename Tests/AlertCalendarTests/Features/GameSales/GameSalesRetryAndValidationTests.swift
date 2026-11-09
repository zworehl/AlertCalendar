import Foundation
import XCTest
@testable import AlertCalendar

final class GameSalesRetryAndValidationTests: IntegrationHTTPTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let steam = "<div class=\"documentation_bbcode\"><h2 class=\"bb_subsection\">Summer Sale | June 25 - July 9, 2027</h2></div>"

    func testManualRefreshCannotBypassPersistedRetryAfterAndRecoversAtDeadline() async throws {
        let log = IntegrationRequestLog()
        let client = GameSalesFeedClient(session: session { request in
            let isSteam = request.url == GameSalesFeedClient.steamworksUpcomingEventsURL
            let attempt = log.record(isSteam ? "steam" : "other")
            if isSteam && attempt == 1 { return self.reply(request, status: 429, headers: ["Retry-After": "600"]) }
            return self.reply(request, body: self.body(request))
        })
        _ = try await client.fetchScheduledSales(now: now)
        _ = try await client.fetchScheduledSales(now: now.addingTimeInterval(1), forceRefresh: true)
        XCTAssertEqual(log.count("steam"), 1)
        _ = try await client.fetchScheduledSales(now: now.addingTimeInterval(600), forceRefresh: true)
        XCTAssertEqual(log.count("steam"), 2)
        let failed = await client.hasPendingRefreshFailures
        XCTAssertFalse(failed)
    }

    func testInvalidHTTP200KeepsValidatedAgeAndMarksPartialData() async throws {
        let log = IntegrationRequestLog()
        let client = GameSalesFeedClient(session: session { request in
            let isSteam = request.url == GameSalesFeedClient.steamworksUpcomingEventsURL
            let attempt = log.record(isSteam ? "steam" : "other")
            let body = isSteam && attempt > 1 ? "<html>maintenance</html>" : self.body(request)
            return self.reply(request, body: body)
        })
        _ = try await client.fetchScheduledSales(now: now)
        _ = try await client.fetchScheduledSales(now: now.addingTimeInterval(61), forceRefresh: true)
        let metrics = await ExternalFeedMetrics.shared.snapshot()
        XCTAssertEqual(metrics.sources["game-sales.steam"]?.lastDataDate, now)
        XCTAssertTrue(metrics.hasUnresolvedFailure(sources: ["game-sales.steam"]))
        XCTAssertEqual(metrics.oldestDataDate(sources: ["game-sales.steam", "game-sales.xbox"]), now)
        XCTAssertGreaterThan(metrics.sources["game-sales.steam"]?.validationFailures ?? 0, 0)
    }

    private func body(_ request: URLRequest) -> String {
        if request.url == GameSalesFeedClient.steamworksUpcomingEventsURL { return steam }
        if request.url == GameSalesFeedClient.nintendoNewsSitemapURL { return "<urlset></urlset>" }
        return "<rss><channel></channel></rss>"
    }
}
