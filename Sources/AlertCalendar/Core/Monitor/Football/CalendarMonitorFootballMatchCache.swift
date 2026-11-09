import Foundation

extension CalendarMonitor {
    func scheduleFootballMatchCacheWrite(
        _ snapshot: FootballMatchCacheSnapshot,
        store: FootballMatchCacheStore
    ) {
        pendingFootballMatchCacheSnapshot = snapshot
        guard !footballState.isShuttingDown else { return }
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
            await self.cacheRepository.saveFootball(pending, store: store)
            self.lastFootballMatchCacheWriteDate = pending.fetchedAt
            self.footballMatchCacheWriteTask = nil
            if let next = self.pendingFootballMatchCacheSnapshot {
                self.scheduleFootballMatchCacheWrite(next, store: store)
            }
        }
    }

    func flushPersistentCachesForTermination() async {
        footballState.isShuttingDown = true
        heartbeatTask?.cancel()
        heartbeatTask = nil
        defaultsObserver = nil
        eventStoreObserver = nil
        workspaceResumeObserver = nil
        appActivationObserver = nil
        refreshCoordinator.task?.cancel()
        calendarAlertFullSyncTask?.cancel()
        eventTitleRewriteTask?.cancel()
        eventTitleRewriteRetryTask?.cancel()
        agendaSummaryTask?.cancel()
        agendaSummaryRetryTask?.cancel()
        footballState.availabilityRefreshTask?.cancel()
        footballState.logoLoadingCoordinator?.cancel()
        let currentWrite = footballMatchCacheWriteTask
        currentWrite?.cancel()
        await currentWrite?.value
        footballMatchCacheWriteTask = nil
        let snapshot = pendingFootballMatchCacheSnapshot
        pendingFootballMatchCacheSnapshot = nil
        await cacheRepository.finish(football: snapshot, store: footballMatchCacheStore)
        if let snapshot { lastFootballMatchCacheWriteDate = snapshot.fetchedAt }
    }
}
