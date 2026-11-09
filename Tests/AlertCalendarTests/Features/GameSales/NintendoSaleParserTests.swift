import Foundation
import XCTest
@testable import AlertCalendar

final class NintendoSaleParserTests: XCTestCase {
    func testSitemapKeepsRecentOfficialArticlesSortedAndDeduplicated() throws {
        let xml = """
        <urlset>
          <url>
            <loc>https://www.nintendo.com/us/whatsnew/indie-sale/</loc>
            <lastmod>2026-05-28T18:13:21.925Z</lastmod>
          </url>
          <url>
            <loc>https://nintendo.com/us/whatsnew/summer-sale/?tracking=ignored</loc>
            <lastmod>2026-06-25T16:12:58.216Z</lastmod>
          </url>
          <url>
            <loc>https://www.nintendo.com/us/whatsnew/summer-sale/</loc>
            <lastmod>2026-06-24T16:12:58Z</lastmod>
          </url>
          <url>
            <loc>https://www.nintendo.com/us/whatsnew/too-old/</loc>
            <lastmod>2026-01-12T20:20:55Z</lastmod>
          </url>
          <url>
            <loc>https://www.nintendo.com.evil.test/us/whatsnew/fake-sale/</loc>
            <lastmod>2026-07-01T00:00:00Z</lastmod>
          </url>
          <url>
            <loc>https://www.nintendo.com/en-ca/whatsnew/wrong-region/</loc>
            <lastmod>2026-07-01T00:00:00Z</lastmod>
          </url>
          <url>
            <loc>https://www.nintendo.com/us/whatsnew/from-the-future/</loc>
            <lastmod>2026-07-14T00:00:00Z</lastmod>
          </url>
        </urlset>
        """

        let references = GameSalesFeedClient.parseNintendoSitemap(
            xml,
            now: try isoDate("2026-07-13T18:00:00Z")
        )

        XCTAssertEqual(references.map(\.url.absoluteString), [
            "https://www.nintendo.com/us/whatsnew/summer-sale/",
            "https://www.nintendo.com/us/whatsnew/indie-sale/",
        ])
        XCTAssertEqual(
            references.first?.lastModified,
            try isoDate("2026-06-25T16:12:58.216Z")
        )
    }

    func testArticleParsesFromNowAgainstPublishedDayInPacificTime() throws {
        let html = articleHTML(
            headline: "Indie Sale: Save on select digital games",
            publishedAt: "2026-05-28T16:00:00.000Z",
            body: """
            <p>Save on hundreds of digital games with the Indie Sale!</p>
            <p>From now until 6/7 at 11:59 p.m. PT.</p>
            <p>Shop the full Indie Sale on Nintendo.com or Nintendo eShop.</p>
            """
        )
        let url = try XCTUnwrap(URL(
            string: "https://www.nintendo.com/us/whatsnew/indie-sale-save-on-select-digital-games/?ref=test"
        ))

        let sale = try XCTUnwrap(GameSalesFeedClient.parseNintendoSaleArticle(
            html,
            url: url,
            now: try isoDate("2026-06-01T12:00:00Z"),
            calendar: utcCalendar
        ))

        XCTAssertEqual(sale.store, .nintendoSwitch)
        XCTAssertEqual(sale.title, "Indie Sale: Save on select digital games")
        XCTAssertEqual(sale.sourceID, "nintendo-us-indie-sale-save-on-select-digital-games")
        XCTAssertEqual(sale.startDate, try pacificDate(2026, 5, 28))
        XCTAssertEqual(sale.endDateExclusive, try pacificDate(2026, 6, 8))
        XCTAssertEqual(
            sale.officialURL.absoluteString,
            "https://www.nintendo.com/us/whatsnew/indie-sale-save-on-select-digital-games/"
        )
    }

    func testArticleParsesExplicitStartAndInclusiveEnd() throws {
        let html = articleHTML(
            headline: "MAR10 Day Sale",
            publishedAt: "2026-03-05T17:00:00Z",
            body: """
            <p>Save on digital games in the Nintendo eShop during this sale.</p>
            <p>The sale starts on March 10 at 12 a.m. PT and lasts until March 23 at 11:59 p.m. PT.</p>
            """
        )

        let sale = try XCTUnwrap(GameSalesFeedClient.parseNintendoSaleArticle(
            html,
            url: try officialURL("mar10-day-sale"),
            now: try isoDate("2026-03-11T12:00:00Z"),
            calendar: utcCalendar
        ))

        XCTAssertEqual(sale.startDate, try pacificDate(2026, 3, 10))
        XCTAssertEqual(sale.endDateExclusive, try pacificDate(2026, 3, 24))
    }

    func testArticleCarriesYearlessJanuaryRangeIntoNextYear() throws {
        let html = articleHTML(
            headline: "New Year eShop Sale",
            publishedAt: "2026-12-20T17:00:00Z",
            body: """
            <p>Save on digital games in Nintendo eShop during this sale.</p>
            <p>The sale runs from January 2 through January 12.</p>
            """
        )

        let sale = try XCTUnwrap(GameSalesFeedClient.parseNintendoSaleArticle(
            html,
            url: try officialURL("new-year-eshop-sale"),
            now: try isoDate("2026-12-21T12:00:00Z"),
            calendar: utcCalendar
        ))

        XCTAssertEqual(sale.startDate, try pacificDate(2027, 1, 2))
        XCTAssertEqual(sale.endDateExclusive, try pacificDate(2027, 1, 13))
    }

    func testArticleRejectsEndOnlyNonSaleExpiredAndDeceptiveHost() throws {
        let endOnly = articleHTML(
            headline: "Summer Sale",
            publishedAt: "2026-06-25T16:00:00Z",
            body: """
            <p>Save on select digital games in the Nintendo eShop.</p>
            <p>This sale ends July 8 at 11:59 p.m. PT.</p>
            """
        )
        XCTAssertNil(GameSalesFeedClient.parseNintendoSaleArticle(
            endOnly,
            url: try officialURL("summer-sale"),
            now: try isoDate("2026-07-01T12:00:00Z")
        ))

        let noDigitalSale = articleHTML(
            headline: "Tournament",
            publishedAt: "2026-06-25T16:00:00Z",
            body: "<p>The tournament runs from June 25 until July 8.</p>"
        )
        XCTAssertNil(GameSalesFeedClient.parseNintendoSaleArticle(
            noDigitalSale,
            url: try officialURL("tournament"),
            now: try isoDate("2026-07-01T12:00:00Z")
        ))

        let expired = articleHTML(
            headline: "Indie Sale",
            publishedAt: "2026-05-28T16:00:00Z",
            body: "<p>Digital games in the Nintendo eShop are on sale from now until June 7.</p>"
        )
        XCTAssertNil(GameSalesFeedClient.parseNintendoSaleArticle(
            expired,
            url: try officialURL("indie-sale"),
            now: try isoDate("2026-06-09T12:00:00Z")
        ))

        let deceptiveURL = try XCTUnwrap(URL(
            string: "https://www.nintendo.com.evil.test/us/whatsnew/indie-sale/"
        ))
        XCTAssertNil(GameSalesFeedClient.parseNintendoSaleArticle(
            expired,
            url: deceptiveURL,
            now: try isoDate("2026-06-01T12:00:00Z")
        ))
    }

    func testArticleRequiresStructuredPromotionsTag() throws {
        let html = articleHTML(
            headline: "Indie Sale",
            publishedAt: "2026-05-28T16:00:00Z",
            body: "<p>Digital games in Nintendo eShop are on sale from now until June 7.</p>",
            includePromotionsTag: false
        )

        XCTAssertNil(GameSalesFeedClient.parseNintendoSaleArticle(
            html,
            url: try officialURL("indie-sale"),
            now: try isoDate("2026-06-01T12:00:00Z")
        ))
    }

    private func articleHTML(
        headline: String,
        publishedAt: String,
        body: String,
        includePromotionsTag: Bool = true
    ) -> String {
        let tag = includePromotionsTag
            ? #"<script id="__NEXT_DATA__">{"tag":{"id":"articleCategoryPromotions"}}</script>"#
            : #"<script id="__NEXT_DATA__">{"tag":{"id":"articleCategoryGameNews"}}</script>"#
        return """
        <html><head>
          <script type="application/ld+json">
          {"@context":"https://schema.org","@graph":[{"@type":"NewsArticle","headline":"\(headline)","datePublished":"\(publishedAt)"}]}
          </script>
          \(tag)
        </head><body><h1>\(headline)</h1>\(body)</body></html>
        """
    }

    private func officialURL(_ slug: String) throws -> URL {
        try XCTUnwrap(URL(string: "https://www.nintendo.com/us/whatsnew/\(slug)/"))
    }

    private func isoDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: value))
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func pacificDate(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        return try XCTUnwrap(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day
        )))
    }
}
