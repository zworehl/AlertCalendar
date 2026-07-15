import Foundation
import XCTest
@testable import AlertCalendar

final class FootballDataAPIClientEndpointTests: XCTestCase {
    func testScoreboardURLBuildsDefaultScoreboardEndpoint() throws {
        let url = try XCTUnwrap(
            FootballDataAPIClient.scoreboardURL(
                slug: "uefa.champions",
                dateRange: nil
            )
        )

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "site.api.espn.com")
        XCTAssertEqual(url.path, "/apis/site/v2/sports/soccer/uefa.champions/scoreboard")
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    }

    func testScoreboardURLBuildsDateRangeQuery() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 12)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12)))

        let url = try XCTUnwrap(
            FootballDataAPIClient.scoreboardURL(
                slug: "fifa.world",
                dateRange: (start, end)
            )
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.path, "/apis/site/v2/sports/soccer/fifa.world/scoreboard")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "dates", value: "20260601-20260615")])
    }

    func testSummaryURLsIncludeCompetitionAndAllSportsFallback() throws {
        let match = FootballTestData.match(
            id: "summary-match",
            competitionSlug: " uefa.champions ",
            statusState: .inProgress,
            homeScore: "2",
            awayScore: "1"
        )

        let urls = FootballDataAPIClient.summaryURLs(for: match)

        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0].path, "/apis/site/v2/sports/soccer/uefa.champions/summary")
        XCTAssertEqual(URLComponents(url: urls[0], resolvingAgainstBaseURL: false)?.queryItems, [
            URLQueryItem(name: "event", value: "summary-match"),
        ])
        XCTAssertEqual(urls[1].path, "/apis/site/v2/sports/soccer/all/summary")
    }

    func testSummaryURLsUseOnlyFallbackWhenCompetitionSlugIsBlank() throws {
        let match = FootballTestData.match(
            id: "fallback-only",
            competitionSlug: "   ",
            statusState: .scheduled
        )

        let urls = FootballDataAPIClient.summaryURLs(for: match)

        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.path, "/apis/site/v2/sports/soccer/all/summary")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(urls.first), resolvingAgainstBaseURL: false)?.queryItems, [
            URLQueryItem(name: "event", value: "fallback-only"),
        ])
    }

    func testCacheKeysTrackMutableStatusAndScoreInputs() throws {
        let summaryURL = try XCTUnwrap(URL(string: "https://example.test/summary?event=cache-key"))
        let match = FootballTestData.match(
            id: "cache-key",
            statusState: .inProgress,
            statusText: "62'",
            statusDetailText: "Second Half",
            statusPeriod: 2,
            homeScore: "2",
            awayScore: "1",
            officialWinner: .home,
            homeShootoutScore: 4,
            awayShootoutScore: 2
        )

        XCTAssertEqual(
            FootballDataAPIClient.goalScorersCacheKey(for: match),
            "cache-key|2|1|62'|Second Half|2"
        )
        XCTAssertEqual(
            FootballDataAPIClient.statisticsCacheKey(for: match),
            "cache-key|2|1|62'|2"
        )
        XCTAssertEqual(
            FootballDataAPIClient.summaryRootCacheKey(url: summaryURL, match: match),
            "https://example.test/summary?event=cache-key|cache-key|2|1|62'|inProgress|Second Half|2|home|4-2"
        )
    }

    func testSummaryCacheKeyChangesWithShootoutState() throws {
        let summaryURL = try XCTUnwrap(URL(string: "https://example.test/summary?event=shootout"))
        let earlier = FootballTestData.match(
            id: "shootout",
            statusState: .inProgress,
            statusText: "PEN",
            statusPeriod: 5,
            homeScore: "1",
            awayScore: "1",
            homeShootoutScore: 2,
            awayShootoutScore: 2
        )
        let later = FootballTestData.match(
            id: "shootout",
            statusState: .inProgress,
            statusText: "PEN",
            statusPeriod: 5,
            homeScore: "1",
            awayScore: "1",
            homeShootoutScore: 3,
            awayShootoutScore: 2
        )

        XCTAssertNotEqual(
            FootballDataAPIClient.summaryRootCacheKey(url: summaryURL, match: earlier),
            FootballDataAPIClient.summaryRootCacheKey(url: summaryURL, match: later)
        )
    }
}
