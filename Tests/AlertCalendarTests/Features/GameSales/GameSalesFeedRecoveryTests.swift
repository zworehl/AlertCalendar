import Foundation
import XCTest
@testable import AlertCalendar

extension GameSalesFeedClientTests {
    func testConnectivityRecoveryRetriesOfflineSourceButRespectsServerBackoff() async throws {
        let health = DataRefreshHealth()
        let client = GameSalesFeedClient(session: makeMockSession(), health: health)
        let counter = GameSalesFeedRequestCounter()
        let now = try date(2026, 7, 16, hour: 12)
        GameSalesFeedMockURLProtocol.requestHandler = { [fixture] request in
            let url = try XCTUnwrap(request.url)
            let attempt = counter.record(url)
            if url == GameSalesFeedClient.steamworksUpcomingEventsURL, attempt == 1 {
                throw URLError(.notConnectedToInternet)
            }
            if url == GameSalesFeedClient.xboxWireStoreFeedURL {
                return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)), Data())
            }
            return try Self.successfulResponse(request, steamHTML: fixture)
        }
        _ = try await client.fetchScheduledSales(now: now)
        let willRetry = await client.retryAfterConnectivityRecovery()
        let beforeRetry = await health.snapshot()
        XCTAssertTrue(willRetry)
        XCTAssertEqual(beforeRetry.count, 2, "A path change must not clear an unresolved failure")
        _ = try await client.fetchScheduledSales(now: now.addingTimeInterval(1))
        XCTAssertEqual(counter.count(for: GameSalesFeedClient.steamworksUpcomingEventsURL), 2)
        for url in [GameSalesFeedClient.xboxWireStoreFeedURL, GameSalesFeedClient.playStationStoreFeedURL,
                    GameSalesFeedClient.nintendoNewsSitemapURL] {
            XCTAssertEqual(counter.count(for: url), 1)
        }
        let afterRetry = await health.snapshot()
        XCTAssertEqual(afterRetry.map(\.id), ["game-sales.xbox"])
    }

    func testInvalidSuccessfulDocumentsPreserveCacheAndDoNotReportFreshData() async throws {
        let health = DataRefreshHealth()
        let client = GameSalesFeedClient(session: makeMockSession(), health: health)
        let counter = GameSalesFeedRequestCounter()
        let now = try date(2026, 7, 16, hour: 12)
        GameSalesFeedMockURLProtocol.requestHandler = { [fixture] request in
            let url = try XCTUnwrap(request.url)
            if counter.record(url) == 2 {
                let body = url == GameSalesFeedClient.steamworksUpcomingEventsURL
                    ? "<html><body>Temporarily unavailable</body></html>" : "<rss><channel>"
                return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)), Data(body.utf8))
            }
            return try Self.successfulResponse(request, steamHTML: fixture)
        }
        let initial = try await client.fetchScheduledSales(now: now)
        _ = try await client.fetchScheduledSales(now: now.addingTimeInterval(30))
        let lastValidated = await client.lastSuccessfulRefreshDate
        XCTAssertEqual(lastValidated, now, "Cache reads must not advance network freshness")
        let invalid = try await client.fetchScheduledSales(now: now.addingTimeInterval(60), forceRefresh: true)
        XCTAssertEqual(initial, invalid)
        let invalidDate = await client.lastSuccessfulRefreshDate
        let issues = await health.snapshot()
        XCTAssertNil(invalidDate)
        XCTAssertEqual(issues.count, 4)
        _ = try await client.fetchScheduledSales(now: now.addingTimeInterval(120), forceRefresh: true)
        let recoveredDate = await client.lastSuccessfulRefreshDate
        let recoveredIssues = await health.snapshot()
        XCTAssertEqual(recoveredDate, now.addingTimeInterval(120))
        XCTAssertTrue(recoveredIssues.isEmpty)
    }

    func testNotModifiedWithoutCachedDocumentRemainsAFailure() async throws {
        let client = GameSalesFeedClient(session: makeMockSession(), health: DataRefreshHealth())
        GameSalesFeedMockURLProtocol.requestHandler = { request in
            (try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 304,
                                           httpVersion: nil, headerFields: nil)), Data())
        }
        do {
            _ = try await client.fetchScheduledSales(now: date(2026, 7, 16))
            XCTFail("A 304 with no local document cannot supply valid data")
        } catch let error as GameSalesFeedClient.ClientError {
            XCTAssertEqual(error, .invalidResponse)
        }
        let pending = await client.hasPendingRefreshFailures
        XCTAssertTrue(pending)
    }

    func testCancellationDoesNotCreateAnOutageOrPoisonTheNextRefresh() async throws {
        let health = DataRefreshHealth()
        let client = GameSalesFeedClient(session: makeMockSession(), health: health)
        let now = try date(2026, 7, 16, hour: 12)
        GameSalesFeedMockURLProtocol.requestHandler = { _ in throw URLError(.cancelled) }
        do {
            _ = try await client.fetchScheduledSales(now: now)
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
        let issues = await health.snapshot()
        let pending = await client.hasPendingRefreshFailures
        XCTAssertTrue(issues.isEmpty)
        XCTAssertFalse(pending)
        GameSalesFeedMockURLProtocol.requestHandler = { [fixture] in
            try Self.successfulResponse($0, steamHTML: fixture)
        }
        let recovered = try await client.fetchScheduledSales(now: now.addingTimeInterval(1))
        XCTAssertFalse(recovered.isEmpty)
    }

    func testNintendoArticleFailureRetainsSaleAndRetriesUnchangedSitemap() async throws {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true).appendingPathComponent("game-sales.json")
        defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
        let cacheStore = GameSalesFeedCacheStore(fileURL: cacheURL)
        let health = DataRefreshHealth()
        let client = GameSalesFeedClient(session: makeMockSession(), cacheStore: cacheStore, health: health)
        let counter = GameSalesFeedRequestCounter()
        let now = try date(2026, 7, 16, hour: 12)
        let articleURL = try XCTUnwrap(URL(string: "https://www.nintendo.com/us/whatsnew/summer-sale/"))
        GameSalesFeedMockURLProtocol.requestHandler = { [fixture] request in
            let url = try XCTUnwrap(request.url)
            let attempt = counter.record(url)
            let body: String
            if url == GameSalesFeedClient.nintendoNewsSitemapURL {
                if attempt == 3 {
                    XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"), "An unchanged sitemap must not prevent retrying its failed articles")
                }
                body = "<urlset><url><loc>\(articleURL.absoluteString)</loc><lastmod>2026-07-\(attempt == 1 ? "14" : "15")T00:00:00Z</lastmod></url></urlset>"
            } else if url == articleURL {
                if attempt == 2 { throw URLError(.networkConnectionLost) }
                body = attempt == 3 ? "<html>Temporarily unavailable</html>" : """
                <html><head><script type="application/ld+json">
                {"@graph":[{"@type":"NewsArticle","headline":"Summer Sale \(attempt)","datePublished":"2026-07-14T16:00:00Z"}]}
                </script><script id="__NEXT_DATA__">{"tag":{"id":"articleCategoryPromotions"}}</script></head>
                <body>Save on digital games in Nintendo eShop. The sale runs from July 14 through July 28.</body></html>
                """
            } else { return try Self.successfulResponse(request, steamHTML: fixture) }
            return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                  headerFields: ["ETag": "sitemap-version"])), Data(body.utf8))
        }
        let initial = try await client.fetchScheduledSales(now: now)
        let initialNintendo = initial.filter { $0.store == .nintendoSwitch }
        XCTAssertEqual(initialNintendo.count, 1)
        let outage = try await client.fetchScheduledSales(now: now.addingTimeInterval(60), forceRefresh: true)
        XCTAssertEqual(outage.filter { $0.store == .nintendoSwitch }, initialNintendo)
        let failedCache = try XCTUnwrap(cacheStore.load())
        XCTAssertEqual(failedCache.nintendoArticleLastModified[articleURL.absoluteString], try date(2026, 7, 14))
        let issues = await health.snapshot()
        XCTAssertEqual(issues.map(\.id), ["game-sales.nintendoSitemap"])
        let invalidArticle = try await client.fetchScheduledSales(now: now.addingTimeInterval(120))
        XCTAssertEqual(invalidArticle.filter { $0.store == .nintendoSwitch }, initialNintendo)
        let invalidCache = try XCTUnwrap(cacheStore.load())
        XCTAssertEqual(invalidCache.nintendoArticleLastModified[articleURL.absoluteString], try date(2026, 7, 14))
        let recovered = try await client.fetchScheduledSales(now: now.addingTimeInterval(180), forceRefresh: true)
        XCTAssertEqual(recovered.first { $0.store == .nintendoSwitch }?.title, "Summer Sale 4")
        XCTAssertEqual(counter.count(for: articleURL), 4)
        let recoveredIssues = await health.snapshot()
        XCTAssertTrue(recoveredIssues.isEmpty)
    }

    func testOfflineRefreshKeepsCachedSalesAndClearsIssuesOnlyAfterRecovery() async throws {
        let health = DataRefreshHealth()
        let client = GameSalesFeedClient(session: makeMockSession(), health: health)
        let counter = GameSalesFeedRequestCounter()
        let now = try date(2026, 7, 16, hour: 12)
        GameSalesFeedMockURLProtocol.requestHandler = { [fixture] request in
            let url = try XCTUnwrap(request.url)
            if counter.record(url) == 2 { throw URLError(.notConnectedToInternet) }
            return try Self.successfulResponse(request, steamHTML: fixture)
        }

        let initial = try await client.fetchScheduledSales(now: now)
        let offline = try await client.fetchScheduledSales(now: now.addingTimeInterval(60), forceRefresh: true)
        XCTAssertEqual(initial, offline)
        let pending = await client.hasPendingRefreshFailures
        let issues = await health.snapshot()
        XCTAssertTrue(pending)
        XCTAssertEqual(issues.count, 4)

        _ = try await client.fetchScheduledSales(now: now.addingTimeInterval(119))
        XCTAssertEqual(counter.count(for: GameSalesFeedClient.steamworksUpcomingEventsURL), 2)
        let recovered = try await client.fetchScheduledSales(now: now.addingTimeInterval(120))
        XCTAssertEqual(initial, recovered)
        let stillPending = await client.hasPendingRefreshFailures
        let recoveredIssues = await health.snapshot()
        XCTAssertFalse(stillPending)
        XCTAssertTrue(recoveredIssues.isEmpty)
        XCTAssertEqual(counter.count(for: GameSalesFeedClient.steamworksUpcomingEventsURL), 3)
    }

    func testRepeatedTransportFailuresRetryEachMinuteAndNeverReturnEmptySuccess() async throws {
        let client = GameSalesFeedClient(session: makeMockSession(), health: DataRefreshHealth())
        let counter = GameSalesFeedRequestCounter()
        let now = try date(2026, 7, 16, hour: 12)
        GameSalesFeedMockURLProtocol.requestHandler = { [fixture] request in
            let url = try XCTUnwrap(request.url)
            if counter.record(url) <= 2 { throw URLError(.networkConnectionLost) }
            return try Self.successfulResponse(request, steamHTML: fixture)
        }

        for elapsed in [0.0, 30, 60, 90] {
            do {
                _ = try await client.fetchScheduledSales(now: now.addingTimeInterval(elapsed))
                XCTFail("An empty cache during an outage must remain a failure")
            } catch let error as GameSalesFeedClient.ClientError {
                XCTAssertEqual(error, .transportFailure(code: URLError.networkConnectionLost.rawValue))
            }
        }
        XCTAssertEqual(counter.count(for: GameSalesFeedClient.steamworksUpcomingEventsURL), 2)
        let recovered = try await client.fetchScheduledSales(now: now.addingTimeInterval(120))
        XCTAssertFalse(recovered.isEmpty)
        XCTAssertEqual(counter.count(for: GameSalesFeedClient.steamworksUpcomingEventsURL), 3)
    }

    func testRestartRetriesPersistedOfflineAndLegacyFailuresWithoutDiscardingHealthyCache() async throws {
        for error: GameSalesFeedClient.ClientError? in [nil, .transportFailure(code: URLError.notConnectedToInternet.rawValue)] {
            let cacheURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("game-sales.json")
            defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
            let cacheStore = GameSalesFeedCacheStore(fileURL: cacheURL)
            let counter = GameSalesFeedRequestCounter()
            let session = makeMockSession()
            let now = try date(2026, 7, 16, hour: 12)
            GameSalesFeedMockURLProtocol.requestHandler = { [fixture] request in
                counter.record(try XCTUnwrap(request.url))
                return try Self.successfulResponse(request, steamHTML: fixture)
            }
            let client = GameSalesFeedClient(session: session, cacheStore: cacheStore, health: DataRefreshHealth())
            let initial = try await client.fetchScheduledSales(now: now)
            var persisted = try XCTUnwrap(cacheStore.load())
            persisted.failures["steam"] = GameSalesFeedFailureState(
                consecutiveFailureCount: 6,
                nextRetryAt: now.addingTimeInterval(6 * 60 * 60),
                error: error
            )
            cacheStore.save(persisted)

            let restarted = GameSalesFeedClient(session: session, cacheStore: cacheStore, health: DataRefreshHealth())
            let restored = try await restarted.fetchScheduledSales(now: now.addingTimeInterval(1))
            XCTAssertEqual(initial, restored)
            XCTAssertEqual(counter.count(for: GameSalesFeedClient.steamworksUpcomingEventsURL), 2)
            for url in [GameSalesFeedClient.xboxWireStoreFeedURL, GameSalesFeedClient.playStationStoreFeedURL,
                        GameSalesFeedClient.nintendoNewsSitemapURL] {
                XCTAssertEqual(counter.count(for: url), 1)
            }
        }
    }

}
