import Foundation
import XCTest
@testable import AlertCalendar

final class CalendarCacheRepositoryTests: XCTestCase {
    func testShutdownBarrierKeepsFinalSnapshotAndFlushesPendingTitles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let footballStore = FootballMatchCacheStore(fileURL: directory.appendingPathComponent("matches.json"))
        let titlesStore = EventTitleRewriteCacheStore(fileURL: directory.appendingPathComponent("titles.json"))
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let old = FootballMatchCacheSnapshot(fetchedAt: now, matches: [])
        let latest = FootballMatchCacheSnapshot(fetchedAt: now, matches: [FootballTestData.friendlyMatch(id: "latest", startDate: now, statusState: .scheduled)])
        let repository = CalendarCacheRepository()
        var titles = EventTitleRewriteCacheSnapshot.empty
        titles.record(title: "Saved before exit", for: "event", sourceFingerprint: "source", maximumCharacters: 40, now: now)
        await repository.saveFootball(old, store: footballStore)
        await repository.scheduleTitles(titles, store: titlesStore)
        await repository.finish(football: latest, store: footballStore)
        await repository.saveFootball(old, store: footballStore)
        await repository.scheduleTitles(.empty, store: titlesStore)
        await repository.flushTitles()
        XCTAssertEqual(footballStore.load(now: now)?.matches.map(\.id), ["latest"])
        XCTAssertEqual(titlesStore.load()?.entries["event"]?.title, "Saved before exit")
    }

    func testCoalescedTitleWritesFlushTheLatestSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EventTitleRewriteCacheStore(fileURL: directory.appendingPathComponent("titles.json"))
        let repository = CalendarCacheRepository()
        var snapshot = EventTitleRewriteCacheSnapshot.empty
        for index in 0..<20 {
            snapshot.record(title: "Title \(index)", for: "event", sourceFingerprint: "source", maximumCharacters: 30, now: Date())
            await repository.scheduleTitles(snapshot, store: store)
        }
        await repository.flushTitles()
        XCTAssertEqual(store.load()?.entries["event"]?.title, "Title 19")
    }

    @MainActor
    func testAsyncRestorePreservesNewerMemoryAndRestoresOtherEntriesOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FootballMatchCacheStore(fileURL: directory.appendingPathComponent("matches.json"))
        let titleStore = EventTitleRewriteCacheStore(fileURL: directory.appendingPathComponent("titles.json"))
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        var titleCache = EventTitleRewriteCacheSnapshot.empty
        titleCache.record(title: "Cached title", for: "cached-title", sourceFingerprint: "cached", maximumCharacters: 40, now: now)
        titleCache.record(title: "Old title", for: "shared-title", sourceFingerprint: "old", maximumCharacters: 40, now: now)
        titleStore.save(titleCache)
        let cached = FootballTestData.friendlyMatch(id: "shared", startDate: now, statusState: .inProgress, homeScore: "0")
        let additional = FootballTestData.friendlyMatch(id: "cached-only", startDate: now, statusState: .scheduled)
        store.save(FootballMatchCacheSnapshot(fetchedAt: now, matches: [cached, additional]))
        let suite = "CalendarCacheRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let monitor = CalendarMonitor(defaults: defaults, footballMatchCacheStore: store, eventTitleRewriteCacheStore: titleStore, startServices: false)
        XCTAssertTrue(monitor.footballMatchesByID.isEmpty, "Constructing the UI monitor must not synchronously decode disk caches")
        monitor.footballMatchesByID["shared"] = FootballTestData.friendlyMatch(
            id: "shared", startDate: now, statusState: .inProgress, homeScore: "2"
        )
        monitor.persistentEventTitleRewriteCache.record(title: "New title", for: "shared-title", sourceFingerprint: "new", maximumCharacters: 40, now: now)
        async let first: Void = monitor.restorePersistentCachesIfNeeded()
        async let second: Void = monitor.restorePersistentCachesIfNeeded()
        _ = await (first, second)
        XCTAssertEqual(monitor.footballMatchesByID["shared"]?.homeScore, "2")
        XCTAssertNotNil(monitor.footballMatchesByID["cached-only"])
        XCTAssertTrue(monitor.didRestorePersistentCaches)
        XCTAssertNotNil(monitor.persistentCacheLoadDuration)
        XCTAssertEqual(monitor.persistentEventTitleRewriteCache.entries["shared-title"]?.title, "New title")
        XCTAssertEqual(monitor.persistentEventTitleRewriteCache.entries["cached-title"]?.title, "Cached title")
        store.save(FootballMatchCacheSnapshot(fetchedAt: now, matches: []))
        await monitor.restorePersistentCachesIfNeeded()
        XCTAssertEqual(monitor.footballMatchesByID.count, 2, "Repeated callers must not replace an already restored snapshot")
    }

    func testRepositoryRestoresOnlyCompatibleCachesAndWritesAvailability() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let availability = FootballCompetitionAvailabilityStore(fileURL: directory.appendingPathComponent("availability.json"))
        let entry = FootballCompetitionAvailability(
            competitionSlug: "eng.1", fetchedAt: now,
            window: .init(now: now, lookbackDays: 1, lookaheadDays: 1), matches: []
        )
        let repository = CalendarCacheRepository()
        await repository.saveAvailability(["eng.1": entry], store: availability)
        let snapshot = await repository.load(titles: nil, football: nil, availability: availability, now: now)
        XCTAssertEqual(snapshot.availability.count, 1)
        XCTAssertNil(snapshot.titles)
        XCTAssertNil(snapshot.football)
        let expired = await repository.load(titles: nil, football: nil, availability: availability, now: now.addingTimeInterval(8 * 86_400))
        XCTAssertTrue(expired.availability.isEmpty)
    }
}
