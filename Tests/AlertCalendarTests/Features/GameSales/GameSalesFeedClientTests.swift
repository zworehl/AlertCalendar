import Foundation
import XCTest
@testable import AlertCalendar

final class GameSalesFeedMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            XCTFail("Missing request handler")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class GameSalesFeedRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [URL: Int] = [:]

    @discardableResult
    func record(_ url: URL) -> Int {
        lock.lock()
        counts[url, default: 0] += 1
        let count = counts[url, default: 0]
        lock.unlock()
        return count
    }

    func count(for url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[url, default: 0]
    }
}

final class GameSalesFeedClientTests: XCTestCase {
    let fixture = """
    <div class="documentation_bbcode">
      <h2 class="bb_subsection"><a name="3"></a>Spring Sale | March 19 - 26, 2026 (ENDED)</h2>
      <h2 class="bb_subsection"><a name="4"></a>Summer Sale | June 25 - July 9, 2026</h2>
      <h2 class="bb_subsection"><a name="5"></a>Autumn Sale | October 1 - October 8, 2026</h2>
      <h2 class="bb_subsection"><a name="6"></a>Winter Sale | December 17 - January 4, 2027</h2>
      <h2 class="bb_subsection"><a name="8"></a><strong>2026 Fests</strong></h2>
      <table>
        <tr><th>Event Dates</th><th>Theme</th><th>Registration</th><th>Eligibility</th></tr>
        <tr>
          <td>July 13<br>July 16</td>
          <td>Social Deduction Fest</td>
          <td>Registration</td>
          <td><a href="https://partner.steamgames.com/doc/marketing/upcoming_events/themed_sales/social_deduction_2026">More info</a></td>
        </tr>
        <tr>
          <td>July 13<br>July 16</td>
          <td>Social Deduction Fest</td>
          <td>Duplicate</td>
          <td><a href="https://partner.steamgames.com/doc/marketing/upcoming_events/themed_sales/social_deduction_2026">More info</a></td>
        </tr>
        <tr>
          <td>July 20<br>July 27</td>
          <td>Train Fest</td>
          <td>Registration</td>
          <td><a href="https://partner.steamgames.com/doc/marketing/upcoming_events/themed_sales/train_2026">More info</a></td>
        </tr>
        <tr>
          <td>Aug 17<br>Aug 20</td>
          <td>Pins &amp; Pegs Fest</td>
          <td>Registration</td>
          <td><a href="https://example.test/not-steam">Untrusted info</a></td>
        </tr>
        <tr><td>not a date</td><td>Broken Fest</td><td>-</td><td>-</td></tr>
        <tr><td>Oct 19<br>Oct 26</td><td>Next Fest</td><td>-</td><td>-</td></tr>
      </table>
      <h2 class="bb_section"><a name="9"></a>Next Fest</h2>
      <h2 class="bb_subsection"><a name="13"></a><strong>Next Fest</strong> | October 19 - October 26, 2026</h2>
    </div>
    """

    override func tearDown() {
        GameSalesFeedMockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testParserBuildsUpcomingSteamSalesWithInclusiveEndDates() throws {
        let calendar = utcCalendar
        let now = try date(2026, 7, 16, hour: 12)

        let sales = GameSalesFeedClient.parseScheduledSales(
            fromHTML: fixture,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(sales.map(\.title), [
            "Steam Social Deduction Fest",
            "Steam Train Fest",
            "Steam Pins & Pegs Fest",
            "Steam Autumn Sale",
            "Steam Winter Sale",
        ])
        XCTAssertEqual(Set(sales.map(\.store)), [.steam])
        XCTAssertTrue(sales.allSatisfy(\.isAllDay))

        let socialDeduction = try XCTUnwrap(
            sales.first { $0.sourceID == "themed-social-deduction-fest-2026" }
        )
        XCTAssertEqual(socialDeduction.startDate, try date(2026, 7, 13))
        XCTAssertEqual(socialDeduction.endDateExclusive, try date(2026, 7, 17))
        XCTAssertEqual(
            socialDeduction.officialURL.absoluteString,
            "https://partner.steamgames.com/doc/marketing/upcoming_events/themed_sales/social_deduction_2026"
        )

        let autumn = try XCTUnwrap(
            sales.first { $0.sourceID == "seasonal-autumn-2026" }
        )
        XCTAssertEqual(autumn.startDate, try date(2026, 10, 1))
        XCTAssertEqual(autumn.endDateExclusive, try date(2026, 10, 9))
        XCTAssertEqual(autumn.officialURL.fragment, "5")

        let winter = try XCTUnwrap(
            sales.first { $0.sourceID == "seasonal-winter-2026" }
        )
        XCTAssertEqual(winter.startDate, try date(2026, 12, 17))
        XCTAssertEqual(winter.endDateExclusive, try date(2027, 1, 5))

        let pinsAndPegs = try XCTUnwrap(
            sales.first { $0.sourceID == "themed-pins-pegs-fest-2026" }
        )
        XCTAssertEqual(
            pinsAndPegs.officialURL,
            GameSalesFeedClient.steamworksUpcomingEventsURL
        )
        XCTAssertFalse(sales.contains { $0.title.localizedCaseInsensitiveContains("Next Fest") })
        XCTAssertFalse(sales.contains { $0.title == "Steam Broken Fest" })
    }

    func testParserDropsSaleAtItsExclusiveEndBoundary() throws {
        let sales = GameSalesFeedClient.parseScheduledSales(
            fromHTML: fixture,
            now: try date(2026, 7, 17),
            calendar: utcCalendar
        )

        XCTAssertFalse(sales.contains { $0.title == "Steam Social Deduction Fest" })
        XCTAssertTrue(sales.contains { $0.title == "Steam Train Fest" })
    }

    func testFetchUsesOfficialEnglishScheduleAndHonorsCacheAndForceRefresh() async throws {
        let session = makeMockSession()
        let client = GameSalesFeedClient(session: session)
        let now = try date(2026, 7, 16, hour: 12)
        let requestCounter = GameSalesFeedRequestCounter()

        GameSalesFeedMockURLProtocol.requestHandler = { [fixture] request in
            let url = try XCTUnwrap(request.url)
            requestCounter.record(url)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Language"), "en-US,en;q=0.9")

            let body: String
            let contentType: String
            switch url {
            case GameSalesFeedClient.steamworksUpcomingEventsURL:
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "Accept"),
                    "text/html,application/xhtml+xml"
                )
                body = fixture
                contentType = "text/html; charset=utf-8"
            case GameSalesFeedClient.xboxWireStoreFeedURL,
                 GameSalesFeedClient.playStationStoreFeedURL:
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "Accept"),
                    "application/rss+xml,application/xml,text/xml"
                )
                body = "<rss><channel></channel></rss>"
                contentType = "application/rss+xml; charset=utf-8"
            case GameSalesFeedClient.nintendoNewsSitemapURL:
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "Accept"),
                    "application/rss+xml,application/xml,text/xml"
                )
                body = "<urlset></urlset>"
                contentType = "text/xml; charset=utf-8"
            default:
                XCTFail("Unexpected game-sale URL: \(url)")
                throw URLError(.badURL)
            }

            let response = try XCTUnwrap(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": contentType]
            ))
            return (response, Data(body.utf8))
        }

        let first = try await client.fetchScheduledSales(now: now)
        let cached = try await client.fetchScheduledSales(
            now: now.addingTimeInterval(60)
        )
        let refreshed = try await client.fetchScheduledSales(
            now: now.addingTimeInterval(120),
            forceRefresh: true
        )

        XCTAssertEqual(first, cached)
        XCTAssertEqual(first, refreshed)
        for url in [
            GameSalesFeedClient.steamworksUpcomingEventsURL,
            GameSalesFeedClient.xboxWireStoreFeedURL,
            GameSalesFeedClient.playStationStoreFeedURL,
            GameSalesFeedClient.nintendoNewsSitemapURL,
        ] {
            XCTAssertEqual(requestCounter.count(for: url), 2)
        }
    }

    func testFetchKeepsSuccessfulOfficialSourcesWhenAnotherSourceFails() async throws {
        let session = makeMockSession()
        let client = GameSalesFeedClient(session: session)

        GameSalesFeedMockURLProtocol.requestHandler = { [fixture] request in
            let url = try XCTUnwrap(request.url)
            let succeeds = url == GameSalesFeedClient.steamworksUpcomingEventsURL
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url,
                statusCode: succeeds ? 200 : 503,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, succeeds ? Data(fixture.utf8) : Data())
        }

        let sales = try await client.fetchScheduledSales(
            now: try date(2026, 7, 16, hour: 12)
        )

        XCTAssertFalse(sales.isEmpty)
        XCTAssertEqual(Set(sales.map(\.store)), [.steam])
    }

    func testFetchPreservesCachedStoreCampaignsDuringPartialOutage() async throws {
        let session = makeMockSession()
        let client = GameSalesFeedClient(session: session)
        let requestCounter = GameSalesFeedRequestCounter()

        GameSalesFeedMockURLProtocol.requestHandler = { [fixture] request in
            let url = try XCTUnwrap(request.url)
            let count = requestCounter.record(url)
            let steamIsUnavailable = url == GameSalesFeedClient.steamworksUpcomingEventsURL
                && count > 1
            let statusCode = steamIsUnavailable ? 503 : 200
            let body: String
            if url == GameSalesFeedClient.steamworksUpcomingEventsURL {
                body = fixture
            } else if url == GameSalesFeedClient.nintendoNewsSitemapURL {
                body = "<urlset></urlset>"
            } else {
                body = "<rss><channel></channel></rss>"
            }
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data(body.utf8))
        }

        let now = try date(2026, 7, 16, hour: 12)
        let initial = try await client.fetchScheduledSales(now: now)
        let duringOutage = try await client.fetchScheduledSales(
            now: now.addingTimeInterval(60),
            forceRefresh: true
        )

        XCTAssertEqual(initial, duringOutage)
        XCTAssertFalse(duringOutage.isEmpty)
    }

    func testPartialOutageRetriesOnlyFailedSourceWhenBackoffExpires() async throws {
        let session = makeMockSession()
        let client = GameSalesFeedClient(session: session)
        let requestCounter = GameSalesFeedRequestCounter()
        let now = try date(2026, 7, 16, hour: 12)

        GameSalesFeedMockURLProtocol.requestHandler = { [fixture] request in
            let url = try XCTUnwrap(request.url)
            let count = requestCounter.record(url)
            let isRetriableSteamFailure = url == GameSalesFeedClient.steamworksUpcomingEventsURL
                && count == 2
            let body: String
            if url == GameSalesFeedClient.steamworksUpcomingEventsURL {
                body = fixture
            } else if url == GameSalesFeedClient.nintendoNewsSitemapURL {
                body = "<urlset></urlset>"
            } else {
                body = "<rss><channel></channel></rss>"
            }
            return (
                try XCTUnwrap(HTTPURLResponse(
                    url: url,
                    statusCode: isRetriableSteamFailure ? 503 : 200,
                    httpVersion: nil,
                    headerFields: nil
                )),
                Data(body.utf8)
            )
        }

        _ = try await client.fetchScheduledSales(now: now)
        _ = try await client.fetchScheduledSales(
            now: now.addingTimeInterval(60),
            forceRefresh: true
        )
        _ = try await client.fetchScheduledSales(now: now.addingTimeInterval(60 + 899))
        _ = try await client.fetchScheduledSales(now: now.addingTimeInterval(60 + 900))

        XCTAssertEqual(requestCounter.count(for: GameSalesFeedClient.steamworksUpcomingEventsURL), 3)
        for url in [
            GameSalesFeedClient.xboxWireStoreFeedURL,
            GameSalesFeedClient.playStationStoreFeedURL,
            GameSalesFeedClient.nintendoNewsSitemapURL,
        ] {
            XCTAssertEqual(requestCounter.count(for: url), 2)
        }
    }

    func testFetchSurfacesUnsuccessfulResponse() async throws {
        let session = makeMockSession()
        let client = GameSalesFeedClient(session: session)
        GameSalesFeedMockURLProtocol.requestHandler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }

        do {
            _ = try await client.fetchScheduledSales(now: try date(2026, 7, 16))
            XCTFail("Expected the client to reject an unsuccessful HTTP response")
        } catch let error as GameSalesFeedClient.ClientError {
            XCTAssertEqual(error, .unsuccessfulResponse(statusCode: 503))
        }
    }

    func testConditionalRefreshReusesCachedDocumentsOnNotModified() async throws {
        let session = makeMockSession()
        let client = GameSalesFeedClient(session: session)
        let requestCounter = GameSalesFeedRequestCounter()
        let now = try date(2026, 7, 16, hour: 12)

        GameSalesFeedMockURLProtocol.requestHandler = { [fixture] request in
            let url = try XCTUnwrap(request.url)
            let count = requestCounter.record(url)
            if count > 1 {
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"feed-v1\"")
            }
            let body: String
            if url == GameSalesFeedClient.steamworksUpcomingEventsURL {
                body = fixture
            } else if url == GameSalesFeedClient.nintendoNewsSitemapURL {
                body = "<urlset></urlset>"
            } else {
                body = "<rss><channel></channel></rss>"
            }
            return (
                try XCTUnwrap(HTTPURLResponse(
                    url: url,
                    statusCode: count > 1 ? 304 : 200,
                    httpVersion: nil,
                    headerFields: ["ETag": "\"feed-v1\""]
                )),
                count > 1 ? Data() : Data(body.utf8)
            )
        }

        let initial = try await client.fetchScheduledSales(now: now)
        let revalidated = try await client.fetchScheduledSales(
            now: now.addingTimeInterval(60),
            forceRefresh: true
        )

        XCTAssertEqual(initial, revalidated)
        XCTAssertFalse(revalidated.isEmpty)
    }

    func testPersistentCacheAvoidsNetworkAfterClientRestart() async throws {
        let session = makeMockSession()
        let requestCounter = GameSalesFeedRequestCounter()
        let now = try date(2026, 7, 16, hour: 12)
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("game-sales.json")
        let cacheStore = GameSalesFeedCacheStore(fileURL: cacheURL)
        defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }

        GameSalesFeedMockURLProtocol.requestHandler = { [fixture] request in
            let url = try XCTUnwrap(request.url)
            requestCounter.record(url)
            let body: String
            if url == GameSalesFeedClient.steamworksUpcomingEventsURL {
                body = fixture
            } else if url == GameSalesFeedClient.nintendoNewsSitemapURL {
                body = "<urlset></urlset>"
            } else {
                body = "<rss><channel></channel></rss>"
            }
            return (
                try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)),
                Data(body.utf8)
            )
        }

        let firstClient = GameSalesFeedClient(session: session, cacheStore: cacheStore)
        let initial = try await firstClient.fetchScheduledSales(now: now)
        let secondClient = GameSalesFeedClient(session: session, cacheStore: cacheStore)
        let restored = try await secondClient.fetchScheduledSales(now: now.addingTimeInterval(60))

        XCTAssertEqual(initial, restored)
        for url in [
            GameSalesFeedClient.steamworksUpcomingEventsURL,
            GameSalesFeedClient.xboxWireStoreFeedURL,
            GameSalesFeedClient.playStationStoreFeedURL,
            GameSalesFeedClient.nintendoNewsSitemapURL,
        ] {
            XCTAssertEqual(requestCounter.count(for: url), 1)
        }
    }

    static func successfulResponse(_ request: URLRequest, steamHTML: String) throws -> (HTTPURLResponse, Data) {
        let url = try XCTUnwrap(request.url)
        let body = url == GameSalesFeedClient.steamworksUpcomingEventsURL ? steamHTML
            : url == GameSalesFeedClient.nintendoNewsSitemapURL ? "<urlset></urlset>"
            : "<rss><channel></channel></rss>"
        return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)), Data(body.utf8))
    }

    var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0
    ) throws -> Date {
        try XCTUnwrap(utcCalendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        )))
    }

    func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GameSalesFeedMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}
