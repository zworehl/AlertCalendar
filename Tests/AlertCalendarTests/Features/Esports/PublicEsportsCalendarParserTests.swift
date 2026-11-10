import Foundation
import XCTest
@testable import AlertCalendar

enum PublicEsportsCalendarTestData {
    static let fetchedAt = ISO8601DateFormatter().date(from: "2026-11-10T04:00:00Z")!
    static let from = ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z")!
    static let to = ISO8601DateFormatter().date(from: "2026-11-30T23:59:59Z")!

    static func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "esports-public-calendar", withExtension: "ics"))
        return try Data(contentsOf: url)
    }

    static func event(id: Int = 1711021, title: String = "Alpha vs Beta", start: String = "20261114T190000Z",
                      end: String = "20261114T210000Z", gameName: String = "League of Legends",
                      extra: String = "") -> String {
        "BEGIN:VEVENT\r\nUID:pandascore-\(id)@esports-calendar.local\r\nDTSTART:\(start)\r\nDTEND:\(end)\r\nSUMMARY:\(title)\r\nLOCATION:\(gameName)\r\nCATEGORIES:Esports,\(gameName)\r\nDESCRIPTION:🎮 \(gameName)\\n📋 League: Worlds\\n⚔️ Format: BO5\r\n\(extra)END:VEVENT\r\n"
    }

    static func calendar(_ events: [String]) -> Data {
        Data(("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n" + events.joined() + "END:VCALENDAR\r\n").utf8)
    }

    static func parse(_ data: Data, game: EsportsGame = .leagueOfLegends, trackedIDs: [Int] = []) throws -> PublicEsportsCalendarParser.Result {
        try PublicEsportsCalendarParser.parse(data, game: game, from: from, to: to, trackedIDs: trackedIDs, fetchedAt: fetchedAt)
    }
}

final class PublicEsportsCalendarParserTests: XCTestCase {
    private typealias Feed = PublicEsportsCalendarTestData

    func testTwelvePublishedEventsAreFilteredLocallyAndKeepCanonicalIdentities() throws {
        let data = try Feed.fixture()
        XCTAssertEqual(String(decoding: data, as: UTF8.self).components(separatedBy: "BEGIN:VEVENT").count - 1, 12)
        for (game, count) in [(EsportsGame.leagueOfLegends, 4), (.counterStrike2, 4), (.starCraft2, 2), (.rocketLeague, 0)] {
            let result = try Feed.parse(data, game: game)
            XCTAssertEqual(result.matches.count, count)
            XCTAssertEqual(result.rejectedEvents, 0)
            XCTAssertTrue(result.matches.allSatisfy { $0.game == game && $0.id == "pandascore:\(game.rawValue):\($0.providerID)" })
        }
    }

    func testRealWorldsResultKeepsTextWithoutInventingParticipantOrScoreIDs() throws {
        let result = try Feed.parse(Feed.fixture())
        let match = try XCTUnwrap(result.matches.first { $0.providerID == 1711019 })
        XCTAssertEqual(match.name, "✅ Bilibili Gaming 3-1 T1")
        XCTAssertEqual(match.status, .finished)
        XCTAssertEqual(match.scheduledAt, ISO8601DateFormatter().date(from: "2026-11-08T22:07:29Z"))
        XCTAssertEqual(match.competitionName, "Worlds")
        XCTAssertEqual(match.competitionKey, "esport-calendar:leagueOfLegends:Worlds")
        XCTAssertNil(match.competitionID)
        XCTAssertTrue(match.opponents.isEmpty)
        XCTAssertTrue(match.results.isEmpty)
        XCTAssertNil(match.winnerID)
        XCTAssertNil(match.endAt, "The publisher's two-hour DTEND is an estimate")
        XCTAssertNil(match.beginAt)
        XCTAssertEqual(match.sourceAttributionText, PublicEsportsCalendarClient.attribution)
        XCTAssertEqual(match.feedSourceURL, PublicEsportsCalendarClient.sourceURL)
        XCTAssertEqual(match.fetchedAt, Feed.fetchedAt)
    }

    func testCRLFSpaceTabUnfoldingAndEscapedUnicodeText() throws {
        var event = Feed.event(title: "Café\\, Inc\\; Pro vs Beta\\\\Club")
        event = event.replacingOccurrences(of: "SUMMARY:Café", with: "SUMMARY:Ca\r\n fé")
        event = event.replacingOccurrences(of: "League: Worlds", with: "League: Liga\r\n\t Ñ\\nOther line")
        let match = try XCTUnwrap(Feed.parse(Feed.calendar([event])).matches.first)
        XCTAssertEqual(match.name, "Café, Inc; Pro vs Beta\\Club")
        XCTAssertEqual(match.competitionName, "Liga Ñ")
    }

    func testFoldBetweenUTF8OctetsIsRestoredBeforeDecoding() throws {
        var bytes = Array(Feed.calendar([Feed.event(title: "Café vs Beta")]))
        let boundary = try XCTUnwrap(bytes.indices.dropLast().first { bytes[$0] == 0xC3 && bytes[$0 + 1] == 0xA9 })
        bytes.insert(contentsOf: [13, 10, 9], at: boundary + 1)
        let match = try XCTUnwrap(Feed.parse(Data(bytes)).matches.first)
        XCTAssertEqual(match.name, "Café vs Beta")
    }

    func testStrictUIDsRejectForeignZeroNegativeOverflowAndMalformedNamespaces() throws {
        let source = Feed.event()
        let valid = "pandascore-1711021@esports-calendar.local"
        for uid in ["random-1711021@esports-calendar.local", "pandascore-0@esports-calendar.local",
                    "pandascore--1@esports-calendar.local", "pandascore-1711021@attacker.test",
                    "pandascore-999999999999999999999999999999@esports-calendar.local", valid + "-extra"] {
            let result = try Feed.parse(Feed.calendar([source.replacingOccurrences(of: valid, with: uid)]))
            XCTAssertTrue(result.matches.isEmpty, uid)
            XCTAssertEqual(result.rejectedEvents, 1, uid)
        }
    }

    func testUTCIsRequiredAndImpossibleDatesCannotBeNormalizedSilently() throws {
        for date in ["20261114T190000", "20261114T190000+0000", "20260230T190000Z", "20261314T190000Z", "20261114T250000Z"] {
            let result = try Feed.parse(Feed.calendar([Feed.event(start: date)]))
            XCTAssertTrue(result.matches.isEmpty, date)
            XCTAssertEqual(result.rejectedEvents, 1, date)
        }
        let floating = Feed.event().replacingOccurrences(of: "DTSTART:", with: "DTSTART;TZID=America/New_York:")
        XCTAssertEqual(try Feed.parse(Feed.calendar([floating])).rejectedEvents, 1)
        let allDay = Feed.event().replacingOccurrences(of: "DTSTART:20261114T190000Z", with: "DTSTART;VALUE=DATE:20261114")
        XCTAssertEqual(try Feed.parse(Feed.calendar([allDay])).rejectedEvents, 1)
        XCTAssertEqual(try Feed.parse(Feed.calendar([Feed.event(end: "20261114T180000Z")])).rejectedEvents, 1)
    }

    func testConflictingDuplicateIdentityIsRemovedWhileOtherMatchesRemain() throws {
        let result = try Feed.parse(Feed.calendar([Feed.event(), Feed.event(title: "Conflicting opponent"), Feed.event(id: 1766739)]))
        XCTAssertEqual(result.matches.map(\.providerID), [1766739])
        XCTAssertEqual(result.rejectedEvents, 1)
        let identical = try Feed.parse(Feed.calendar([Feed.event(), Feed.event()]))
        XCTAssertEqual(identical.matches.count, 1)
        XCTAssertEqual(identical.rejectedEvents, 0)
    }

    func testCancelledLiveAndFinishedStatusRequirePublishedEvidence() throws {
        let cancelled = Feed.event(id: 1, extra: "STATUS:CANCELLED\r\n")
        let live = Feed.event(id: 2, title: "🔴 LIVE: Alpha vs Beta")
        let finished = Feed.event(id: 3, title: "✅ Alpha 3-1 Beta")
            .replacingOccurrences(of: "League: Worlds", with: "League: Worlds\\n✅ Final Score: Alpha 3 - 1 Beta")
        let normal = Feed.event(id: 4)
        let result = try Feed.parse(Feed.calendar([cancelled, live, finished, normal]))
        let statuses = Dictionary(uniqueKeysWithValues: result.matches.map { ($0.providerID, $0.status) })
        XCTAssertEqual(statuses[1], .canceled)
        XCTAssertEqual(statuses[2], .running)
        XCTAssertEqual(statuses[3], .finished)
        XCTAssertEqual(statuses[4], .scheduled)
    }

    func testWindowFilteringRetainsTrackedOutOfWindowAndExplicitlyRunningMatches() throws {
        let old = Feed.event(id: 1, start: "20260101T190000Z", end: "20260101T210000Z")
        let tracked = Feed.event(id: 2, start: "20260101T190000Z", end: "20260101T210000Z")
        let running = Feed.event(id: 3, title: "🔴 LIVE: Alpha vs Beta", start: "20260101T190000Z", end: "20260101T210000Z")
        let result = try Feed.parse(Feed.calendar([old, tracked, running, Feed.event(id: 4)]), trackedIDs: [2])
        XCTAssertEqual(Set(result.matches.map(\.providerID)), [2, 3, 4])
    }

    func testRecurrencesAndDuplicatePropertiesCannotBecomeManagedMatches() throws {
        for extra in ["RRULE:FREQ=WEEKLY\r\n", "RECURRENCE-ID:20261114T190000Z\r\n", "UID:pandascore-42@esports-calendar.local\r\n"] {
            let result = try Feed.parse(Feed.calendar([Feed.event(extra: extra)]))
            XCTAssertTrue(result.matches.isEmpty)
            XCTAssertEqual(result.rejectedEvents, 1)
        }
    }

    func testNestedAlarmDescriptionCannotReplacePublishedLeague() throws {
        let event = Feed.event(extra: "BEGIN:VALARM\r\nACTION:DISPLAY\r\nDESCRIPTION:📋 League: Attacker\r\nEND:VALARM\r\n")
        XCTAssertEqual(try Feed.parse(Feed.calendar([event])).matches.first?.competitionName, "Worlds")
    }

    func testEmptyPropertyNamesRejectOnlyTheirEventWithoutCrashing() throws {
        for line in [":broken\r\n", ";:broken\r\n", ";;;:broken\r\n"] {
            let result = try Feed.parse(Feed.calendar([Feed.event(extra: line), Feed.event(id: 1766739)]))
            XCTAssertEqual(result.matches.map(\.providerID), [1766739])
            XCTAssertEqual(result.rejectedEvents, 1)
        }
    }

    func testUntrustedStreamURLsAreNotOfferedAsActions() throws {
        for url in ["https://twitch.tv.attacker.test/show", "https://secret@twitch.tv/show", "file:///tmp/stream", "http://www.twitch.tv/show"] {
            let result = try Feed.parse(Feed.calendar([Feed.event(extra: "URL:\(url)\r\n")]))
            XCTAssertNil(result.matches.first?.streamURL)
        }
    }

    func testMalformedEnvelopeInvalidUTF8NULAndParserLimitsFailClosed() {
        let invalid = [Data("<html>temporarily unavailable</html>".utf8),
            Data("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nEND:VCALENDAR\r\n".utf8),
            Data("\tBEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n".utf8),
            Data([0xFF, 0xFE]), Data("BEGIN:VCALENDAR\n\0\nEND:VCALENDAR".utf8),
            Data(repeating: 0x61, count: 5_000_001),
            Feed.calendar([Feed.event(title: String(repeating: "x", count: 32_769))]),
            Feed.calendar(Array(repeating: Feed.event(), count: 10_001))]
        for data in invalid {
            XCTAssertThrowsError(try Feed.parse(data)) { XCTAssertEqual($0 as? EsportsFeedError, .invalidPayload) }
        }
    }
}
