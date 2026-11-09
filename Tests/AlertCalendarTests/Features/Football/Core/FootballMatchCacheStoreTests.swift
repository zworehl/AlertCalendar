import Foundation
import XCTest
@testable import AlertCalendar

final class FootballMatchCacheStoreTests: XCTestCase {
    func testMatchCacheRoundTripsCompleteFixtureSnapshot() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlertCalendarFootballMatchCacheTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = FootballMatchCacheStore(
            fileURL: directoryURL.appendingPathComponent("matches.json")
        )
        let fetchedAt = Date(timeIntervalSince1970: 1_720_000_000)
        let probabilities = FootballMatchOutcomeProbabilities(
            homeWin: 0.5,
            draw: 0.3,
            awayWin: 0.2,
            source: .marketOdds,
            scope: .regulationTime,
            observedAt: fetchedAt
        )
        let match = FootballTestData.match(
            id: "cached-match",
            startDate: fetchedAt.addingTimeInterval(3_600),
            statusState: .scheduled,
            pregameOutcomeProbabilities: probabilities
        )

        store.save(FootballMatchCacheSnapshot(fetchedAt: fetchedAt, matches: [match]))
        let loaded = store.load(now: fetchedAt.addingTimeInterval(60))

        XCTAssertEqual(loaded?.fetchedAt, fetchedAt)
        XCTAssertEqual(loaded?.matches, [match])
    }

    func testMatchCacheRejectsExpiredSnapshot() {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlertCalendarFootballMatchCacheExpiryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = FootballMatchCacheStore(
            fileURL: directoryURL.appendingPathComponent("matches.json")
        )
        let fetchedAt = Date(timeIntervalSince1970: 1_720_000_000)
        store.save(FootballMatchCacheSnapshot(fetchedAt: fetchedAt, matches: []))

        XCTAssertNil(
            store.load(
                now: fetchedAt.addingTimeInterval(FootballMatchCacheStore.retentionInterval + 1)
            )
        )
    }
}
