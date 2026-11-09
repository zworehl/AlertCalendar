import Foundation
import XCTest
@testable import AlertCalendar

final class FootballCompetitionAvailabilityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_720_000_000)

    func testActiveAndEmptyAvailabilitySurviveRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FootballCompetitionAvailabilityStore(fileURL: directory.appendingPathComponent("availability.json"))
        let window = FootballCompetitionAvailabilityWindow(now: now, lookbackDays: 7, lookaheadDays: 14)
        let match = FootballTestData.match(id: "available", startDate: now, statusState: .scheduled)
        let active = try XCTUnwrap(FootballCompetitionAvailability.confirmed(
            from: FootballFixtureLoadResult(matches: [match], availablePageCount: 2),
            competitionSlug: "eng.1", window: window, now: now
        ))
        let empty = try XCTUnwrap(FootballCompetitionAvailability.confirmed(
            from: FootballFixtureLoadResult(availablePageCount: 2),
            competitionSlug: "fifa.world", window: window, now: now
        ))
        store.save(["eng.1": active, "fifa.world": empty])

        let restored = FootballCompetitionAvailabilityStore(fileURL: store.fileURL).load(now: now.addingTimeInterval(60))
        XCTAssertEqual(restored["eng.1"]?.matches.map(\.id), ["available"])
        XCTAssertEqual(restored["fifa.world"]?.matches, [])
        XCTAssertEqual(restored["fifa.world"]?.window, window)
        XCTAssertTrue(try XCTUnwrap(restored["fifa.world"]).isFresh(for: window, now: now.addingTimeInterval(60)))
    }

    func testFreshnessRequiresCoverageAndExpiresForHiddenCompetitionsToo() {
        let window = FootballCompetitionAvailabilityWindow(now: now, lookbackDays: 7, lookaheadDays: 14)
        let entry = FootballCompetitionAvailability(competitionSlug: "fifa.world", fetchedAt: now, window: window, matches: [])
        XCTAssertTrue(entry.isFresh(for: window, now: now.addingTimeInterval(60)))
        XCTAssertTrue(entry.isFresh(for: FootballCompetitionAvailabilityWindow(now: now, lookbackDays: 1, lookaheadDays: 1), now: now))
        XCTAssertFalse(entry.isFresh(for: FootballCompetitionAvailabilityWindow(now: now, lookbackDays: 7, lookaheadDays: 90), now: now))
        XCTAssertFalse(entry.isFresh(for: FootballCompetitionAvailabilityWindow(now: now.addingTimeInterval(86_400), lookbackDays: 7, lookaheadDays: 14), now: now))
        XCTAssertFalse(entry.isFresh(for: window, now: now.addingTimeInterval(FootballCompetitionAvailability.refreshInterval)))
        XCTAssertFalse(entry.isFresh(for: window, now: now.addingTimeInterval(-1)))
    }

    func testPartialFailureCannotReplaceLastSuccessfulAvailabilityWithAnEmptyResult() throws {
        let window = FootballCompetitionAvailabilityWindow(now: now, lookbackDays: 7, lookaheadDays: 14)
        let previous = FootballCompetitionAvailability(
            competitionSlug: "eng.1", fetchedAt: now, window: window,
            matches: [FootballTestData.match(id: "last-known", startDate: now, statusState: .scheduled)]
        )
        let failure = FootballFixtureLoadFailure(
            competitionSlug: "eng.1", range: FootballScoreboardDateRange(start: window.start, end: window.end), reason: "Offline"
        )
        let partial = FootballFixtureLoadResult(failures: [failure], availablePageCount: 1)
        let next = FootballCompetitionAvailability.confirmed(from: partial, competitionSlug: "eng.1", window: window, now: now) ?? previous
        XCTAssertEqual(next.matches.map(\.id), ["last-known"])
        XCTAssertNil(FootballCompetitionAvailability.confirmed(
            from: FootballFixtureLoadResult(), competitionSlug: "eng.1", window: window, now: now
        ))
    }

    func testConfirmedEmptyCompetitionCanReturnWhenFixturesArePublished() throws {
        let window = FootballCompetitionAvailabilityWindow(now: now, lookbackDays: 7, lookaheadDays: 14)
        let empty = try XCTUnwrap(FootballCompetitionAvailability.confirmed(
            from: FootballFixtureLoadResult(availablePageCount: 1), competitionSlug: "fifa.world", window: window, now: now
        ))
        XCTAssertTrue(empty.matches.isEmpty)
        let match = FootballTestData.match(id: "newly-published", startDate: now.addingTimeInterval(86_400), statusState: .scheduled)
        let updated = try XCTUnwrap(FootballCompetitionAvailability.confirmed(
            from: FootballFixtureLoadResult(matches: [match], availablePageCount: 1),
            competitionSlug: "fifa.world", window: window, now: now.addingTimeInterval(900)
        ))
        XCTAssertEqual(updated.matches.map(\.id), ["newly-published"])
    }

    func testCacheDiscardsExpiredAndFutureDatedEntries() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FootballCompetitionAvailabilityStore(fileURL: directory.appendingPathComponent("availability.json"))
        let window = FootballCompetitionAvailabilityWindow(now: now, lookbackDays: 7, lookaheadDays: 14)
        store.save([
            "expired": FootballCompetitionAvailability(competitionSlug: "expired", fetchedAt: now.addingTimeInterval(-FootballCompetitionAvailabilityStore.retentionInterval - 1), window: window, matches: []),
            "future": FootballCompetitionAvailability(competitionSlug: "future", fetchedAt: now.addingTimeInterval(1), window: window, matches: [])
        ])
        XCTAssertTrue(store.load(now: now).isEmpty)
    }
}
