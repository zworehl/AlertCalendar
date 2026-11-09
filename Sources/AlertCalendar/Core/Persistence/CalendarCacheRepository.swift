import Foundation

struct CalendarPersistentCacheSnapshot: Sendable {
    let titles: EventTitleRewriteCacheSnapshot?
    let football: FootballMatchCacheSnapshot?
    let availability: [String: FootballCompetitionAvailability]
}

/// Owns disk work independently of the presentation actor. Pending title writes
/// are coalesced so a cache hit for each visible event does not rewrite the file.
actor CalendarCacheRepository {
    private var pendingTitleWrite: (EventTitleRewriteCacheSnapshot, EventTitleRewriteCacheStore)?
    private var titleWriteTask: Task<Void, Never>?
    private var isClosed = false

    func load(
        titles: EventTitleRewriteCacheStore?,
        football: FootballMatchCacheStore?,
        availability: FootballCompetitionAvailabilityStore?,
        now: Date
    ) -> CalendarPersistentCacheSnapshot {
        CalendarPersistentCacheSnapshot(
            titles: titles?.load(),
            football: football?.load(now: now),
            availability: availability?.load(now: now) ?? [:]
        )
    }

    func saveAvailability(
        _ entries: [String: FootballCompetitionAvailability],
        store: FootballCompetitionAvailabilityStore
    ) {
        guard !isClosed else { return }
        store.save(entries)
    }

    func saveFootball(_ snapshot: FootballMatchCacheSnapshot, store: FootballMatchCacheStore) {
        guard !isClosed else { return }
        store.save(snapshot)
    }

    func scheduleTitles(_ snapshot: EventTitleRewriteCacheSnapshot, store: EventTitleRewriteCacheStore) {
        guard !isClosed else { return }
        pendingTitleWrite = (snapshot, store)
        guard titleWriteTask == nil else { return }
        titleWriteTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            await self?.flushTitles()
        }
    }

    func flushTitles() {
        titleWriteTask?.cancel()
        titleWriteTask = nil
        guard let (snapshot, store) = pendingTitleWrite else { return }
        pendingTitleWrite = nil
        store.save(snapshot)
    }

    /// This barrier follows any in-progress write on the same actor. Later
    /// background completions cannot overwrite the final shutdown snapshot.
    func finish(football: FootballMatchCacheSnapshot?, store: FootballMatchCacheStore?) {
        guard !isClosed else { return }
        isClosed = true
        if let football, let store { store.save(football) }
        flushTitles()
    }
}

extension CalendarMonitor {
    /// UI entry points may race with bootstrap. All callers share one restore,
    /// and a late disk snapshot never replaces newer in-memory results.
    func restorePersistentCachesIfNeeded() async {
        guard !didRestorePersistentCaches else { return }
        let startedAt = Date()
        if persistentCacheRestoreTask == nil {
            let titles = eventTitleRewriteCacheStore
            let football = footballMatchCacheStore
            let availability = footballCompetitionAvailabilityStore
            let now = fixedSecondNow()
            let repository = cacheRepository
            persistentCacheRestoreTask = Task {
                await repository.load(titles: titles, football: football, availability: availability, now: now)
            }
        }
        guard let snapshot = await persistentCacheRestoreTask?.value, !didRestorePersistentCaches else { return }
        didRestorePersistentCaches = true
        persistentCacheRestoreTask = nil
        if let titles = snapshot.titles {
            let merged = titles.entries.merging(persistentEventTitleRewriteCache.entries) { _, current in current }
            persistentEventTitleRewriteCache = EventTitleRewriteCacheSnapshot(
                version: EventTitleRewriteCacheSnapshot.currentVersion, entries: merged
            )
        }
        if let football = snapshot.football {
            let cached = Dictionary(football.matches.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            footballMatchesByID = cached.merging(footballMatchesByID) { _, current in current }
            if lastFootballRefreshDate == nil { markFootballRefreshed(at: football.fetchedAt) }
        }
        footballState.availabilityBySlug = snapshot.availability.merging(footballState.availabilityBySlug) {
            cached, current in current.fetchedAt >= cached.fetchedAt ? current : cached
        }
        persistentCacheLoadDuration = Date().timeIntervalSince(startedAt)
        CalendarMonitorLog.refresh.info("Restored persistent caches off the presentation actor in \(self.persistentCacheLoadDuration ?? 0, privacy: .public)s")
    }

    func persistFootballCompetitionAvailability() async {
        guard let store = footballCompetitionAvailabilityStore else { return }
        await cacheRepository.saveAvailability(footballState.availabilityBySlug, store: store)
    }

    func persistTitleRewriteCache() async {
        guard let store = eventTitleRewriteCacheStore else { return }
        await cacheRepository.scheduleTitles(persistentEventTitleRewriteCache, store: store)
    }
}
