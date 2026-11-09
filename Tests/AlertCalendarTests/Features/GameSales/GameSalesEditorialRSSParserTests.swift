import Foundation
import XCTest
@testable import AlertCalendar

final class GameSalesEditorialRSSParserTests: XCTestCase {
    func testXboxParserBuildsInclusiveOfficialSaleRange() throws {
        let xml = rss(item(
            title: "THQ Nordic and HandyGames Publisher Sale 2026",
            link: "https://news.xbox.com/en-us/2026/01/20/thq-nordic-handy-games-sale-2026/?source=rss",
            guid: "https://news.xbox.com/?p=12345",
            published: "Tue, 20 Jan 2026 17:00:00 +0000",
            content: "Save in this publisher sale from January 20 through February 2."
        ))

        let sales = GameSalesEditorialRSSParser.parseEditorialRSS(
            xml: xml,
            store: .xbox,
            now: try date(2026, 1, 21),
            calendar: utcCalendar
        )

        let sale = try XCTUnwrap(sales.first)
        XCTAssertEqual(sales.count, 1)
        XCTAssertEqual(sale.store, .xbox)
        XCTAssertEqual(sale.startDate, try date(2026, 1, 20))
        XCTAssertEqual(sale.endDateExclusive, try date(2026, 2, 3))
        XCTAssertEqual(sale.sourceID, "editorial-https-news-xbox-com-p-12345")
        XCTAssertEqual(
            sale.officialURL.absoluteString,
            "https://news.xbox.com/en-us/2026/01/20/thq-nordic-handy-games-sale-2026/"
        )
    }

    func testPlayStationParserTreatsMidnightEndAsExclusive() throws {
        let xml = rss(item(
            title: "The Spring Sale comes to PlayStation Store March 25",
            link: "https://blog.playstation.com/2026/03/24/the-spring-sale-comes-to-playstation-store-march-25/",
            guid: "urn:uuid:1D2555E0-54DB-4F3B-A43B-991F9A13B342",
            published: "Tue, 24 Mar 2026 15:00:00 +0000",
            content: "The Spring Sale starts March 25 at 00:00 AM PDT and ends April 23 at 00:00 AM PDT."
        ))

        let sale = try XCTUnwrap(
            GameSalesEditorialRSSParser.parseEditorialRSS(
                xml: xml,
                store: .playStation,
                now: try date(2026, 3, 24),
                calendar: utcCalendar
            ).first
        )

        XCTAssertEqual(sale.startDate, try date(2026, 3, 25))
        XCTAssertEqual(sale.endDateExclusive, try date(2026, 4, 23))
        XCTAssertEqual(sale.sourceID, "editorial-urn-uuid-1d2555e0-54db-4f3b-a43b-991f9a13b342")
    }

    func testParserAnchorsStartingTodayToPublicationDate() throws {
        let xml = rss(item(
            title: "Square Enix Publisher Sale",
            link: "https://news.xbox.com/en-us/2025/03/18/square-enix-publisher-sale-march-2025/",
            guid: "xbox-square-enix-2025",
            published: "Tue, 18 Mar 2025 22:30:00 +0000",
            content: "Starting today, this Xbox sale lasts until March 31 at 11:59 p.m. PT."
        ))

        let sale = try XCTUnwrap(
            GameSalesEditorialRSSParser.parseEditorialRSS(
                xml: xml,
                store: .xbox,
                now: try date(2025, 3, 20),
                calendar: utcCalendar
            ).first
        )

        XCTAssertEqual(sale.startDate, try date(2025, 3, 18))
        XCTAssertEqual(sale.endDateExclusive, try date(2025, 4, 1))
    }

    func testParserRejectsIncompleteExpiredRegionalAndUntrustedItems() throws {
        let xml = rss([
            item(
                title: "Xbox Summer Sale",
                link: "https://news.xbox.com/en-us/2026/07/06/summer-sale/",
                guid: "incomplete",
                published: "Mon, 06 Jul 2026 12:00:00 +0000",
                content: "The Xbox sale ends July 20."
            ),
            item(
                title: "PlayStation Store Sale",
                link: "https://blog.playstation.com.evil.test/2026/sale/",
                guid: "untrusted",
                published: "Mon, 06 Jul 2026 12:00:00 +0000",
                content: "The sale runs from July 6 through July 20."
            ),
            item(
                title: "PlayStation Store Sale (For Southeast Asia)",
                link: "https://blog.playstation.com/2026/07/06/regional-sale/",
                guid: "regional",
                published: "Mon, 06 Jul 2026 12:00:00 +0000",
                content: "The sale runs from July 6 through July 20."
            ),
            item(
                title: "PlayStation Spring Sale",
                link: "https://blog.playstation.com/2026/03/01/spring-sale/",
                guid: "expired",
                published: "Sun, 01 Mar 2026 12:00:00 +0000",
                content: "The sale runs from March 1 through March 10."
            ),
        ])

        XCTAssertTrue(GameSalesEditorialRSSParser.parseEditorialRSS(
            xml: xml,
            store: .playStation,
            now: try date(2026, 7, 13),
            calendar: utcCalendar
        ).isEmpty)
    }

    func testParserRejectsMalformedRSSAndUnsupportedStore() throws {
        XCTAssertTrue(GameSalesEditorialRSSParser.parseEditorialRSS(
            xml: "<rss><item>",
            store: .xbox,
            now: try date(2026, 7, 13),
            calendar: utcCalendar
        ).isEmpty)
        XCTAssertTrue(GameSalesEditorialRSSParser.parseEditorialRSS(
            xml: rss(item(
                title: "Steam Sale",
                link: "https://store.steampowered.com/",
                guid: "steam",
                published: "Mon, 13 Jul 2026 12:00:00 +0000",
                content: "The sale runs from July 13 through July 20."
            )),
            store: .steam,
            now: try date(2026, 7, 13),
            calendar: utcCalendar
        ).isEmpty)
    }

    private func rss(_ item: String) -> String {
        rss([item])
    }

    private func rss(_ items: [String]) -> String {
        "<rss><channel>\(items.joined())</channel></rss>"
    }

    private func item(
        title: String,
        link: String,
        guid: String,
        published: String,
        content: String
    ) -> String {
        """
        <item>
          <title><![CDATA[\(title)]]></title>
          <link>\(link.replacingOccurrences(of: "&", with: "&amp;"))</link>
          <guid><![CDATA[\(guid)]]></guid>
          <pubDate>\(published)</pubDate>
          <content:encoded><![CDATA[<p>\(content)</p>]]></content:encoded>
        </item>
        """
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(utcCalendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day
        )))
    }
}
