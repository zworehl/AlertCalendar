import Foundation

extension CalendarMonitor {
    func scheduleFootballMatchCacheWrite(
        _ snapshot: FootballMatchCacheSnapshot,
        store: FootballMatchCacheStore
    ) {
        pendingFootballMatchCacheSnapshot = snapshot
        guard footballMatchCacheWriteTask == nil else { return }

        let minimumInterval: TimeInterval = 5 * 60
        let elapsed = lastFootballMatchCacheWriteDate.map {
            snapshot.fetchedAt.timeIntervalSince($0)
        } ?? minimumInterval
        let delay = max(0, minimumInterval - elapsed)
        footballMatchCacheWriteTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled, let self,
                  let pending = self.pendingFootballMatchCacheSnapshot else { return }
            self.pendingFootballMatchCacheSnapshot = nil
            await Task.detached(priority: .utility) {
                store.save(pending)
            }.value
            self.lastFootballMatchCacheWriteDate = pending.fetchedAt
            self.footballMatchCacheWriteTask = nil
            if let next = self.pendingFootballMatchCacheSnapshot {
                self.scheduleFootballMatchCacheWrite(next, store: store)
            }
        }
    }

    func flushFootballMatchCache() {
        footballMatchCacheWriteTask?.cancel()
        footballMatchCacheWriteTask = nil
        guard let snapshot = pendingFootballMatchCacheSnapshot,
              let footballMatchCacheStore else { return }
        pendingFootballMatchCacheSnapshot = nil
        footballMatchCacheStore.save(snapshot)
        lastFootballMatchCacheWriteDate = snapshot.fetchedAt
    }
}
