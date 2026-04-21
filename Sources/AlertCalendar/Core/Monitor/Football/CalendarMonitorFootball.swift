import AppKit
import CoreLocation
import EventKit
import Foundation

struct ManagedFootballEventSnapshot {
    let event: EKEvent
    let reference: ManagedFootballFixtureReference
    let record: ManagedFootballEventRecord
}

extension CalendarMonitor {
    static let footballMenuRefreshInterval: TimeInterval = 60
    static let footballManagedSyncInterval: TimeInterval = 60
    static let footballManagedCleanupInterval: TimeInterval = 6 * 60 * 60
    static let footballManagedRecoveryInterval: TimeInterval = 15 * 60
    static let footballLegacyMigrationInterval: TimeInterval = 6 * 60 * 60
    static let footballTrackedLookbackDays = FootballCompetitionPreset.suggestionWindowLookbackDays
    static let footballTrackedLookaheadDays = FootballCompetitionPreset.suggestionWindowLookaheadDays
    static let footballManagedCleanupSearchLookbackDays = 365
    static let footballManagedCleanupSearchLookaheadDays = 365
    nonisolated static let footballRegulationMatchDuration: TimeInterval = 110 * 60
    nonisolated static let footballExtraTimeMatchDuration: TimeInterval = 140 * 60
    nonisolated static let footballPenaltyMatchDuration: TimeInterval = 150 * 60
    nonisolated static let footballLiveMinimumTailDuration: TimeInterval = 10 * 60
    nonisolated static let footballEstimatedEndMarginDuration: TimeInterval = 5 * 60
    nonisolated static let footballManagedEventMatchingTolerance: TimeInterval = 5 * 60
    nonisolated static let footballStructuredLocationToleranceMeters: CLLocationDistance = 150

    func refreshFootballDataIfNeeded(now: Date, force: Bool = false) async {
        await syncManagedFootballEventsIfNeeded(now: now, force: force)
    }

    func invalidateManagedFootballSnapshotCache(markEventStoreChanged: Bool = false) {
        cachedManagedFootballSnapshots = []
        isManagedFootballSnapshotCacheValid = false
        if markEventStoreChanged {
            didFootballEventStoreChange = true
        }
    }

    func shouldRunFootballLegacyMigration(now: Date, force: Bool) -> Bool {
        force
            || didFootballEventStoreChange
            || lastFootballLegacyMigrationDate == nil
            || now.timeIntervalSince(lastFootballLegacyMigrationDate!) >= Self.footballLegacyMigrationInterval
    }

    func shouldRunFootballManagedRecovery(now: Date, force: Bool) -> Bool {
        force
            || didFootballEventStoreChange
            || managedFootballEventRecords.isEmpty
            || lastFootballManagedRecoveryDate == nil
            || now.timeIntervalSince(lastFootballManagedRecoveryDate!) >= Self.footballManagedRecoveryInterval
    }

    func ensureFootballCompetitionSections() {
        let existingSectionsByID = Dictionary(uniqueKeysWithValues: footballMenuSections.map { ($0.id, $0) })
        let nextSections = FootballCompetitionPreset.menuPresets.map { preset in
            existingSectionsByID[preset.id] ?? Self.defaultFootballCompetitionSection(for: preset)
        }
        guard footballMenuSections != nextSections else { return }
        footballMenuSections = nextSections
    }

    func loadFootballCompetitionSection(_ competition: FootballCompetitionPreset, force: Bool = true) async {
        ensureFootballCompetitionSections()
        guard let existingSection = footballMenuSections.first(where: { $0.id == competition.id }) else { return }
        guard !existingSection.isLoading else { return }
        guard force || !existingSection.hasLoaded else { return }

        let now = fixedSecondNow()
        let cachedMatches = cachedCompetitionMatches(for: competition, now: now)
        let hasCachedMatches = !cachedMatches.isEmpty

        updateFootballCompetitionSection(competition.id) { currentSection in
            FootballMenuCompetitionSection(
                competition: currentSection.competition,
                matches: hasCachedMatches ? cachedMatches : currentSection.matches,
                errorMessage: nil,
                isLoading: true,
                hasLoaded: currentSection.hasLoaded || hasCachedMatches
            )
        }

        do {
            let matchesByCompetition = try await footballClient.fetchMatchesByCompetition(for: [competition])
            let fetchedMatches = matchesByCompetition[competition.slug] ?? []
            let refreshedMatches = await footballClient.refreshStatusesIfNeeded(for: fetchedMatches)
            let resolvedMatches = matchesPreservingKnownTimingContext(refreshedMatches)
            await cacheFootballMatches(resolvedMatches)
            let matches = Self.resolvedFootballSectionMatches(
                resolvedMatches,
                cachedMatchesByID: footballMatchesByID,
                now: now
            )

            updateFootballCompetitionSection(competition.id) { _ in
                FootballMenuCompetitionSection(
                    competition: competition,
                    matches: matches,
                    errorMessage: nil,
                    isLoading: false,
                    hasLoaded: true
                )
            }
        } catch {
            updateFootballCompetitionSection(competition.id) { currentSection in
                FootballMenuCompetitionSection(
                    competition: currentSection.competition,
                    matches: currentSection.matches,
                    errorMessage: currentSection.hasLoaded
                        ? "Could not refresh fixtures right now. Showing cached matches."
                        : "Could not load fixtures right now.",
                    isLoading: false,
                    hasLoaded: currentSection.hasLoaded
                )
            }
        }
    }

    func loadFootballLiveAndNextDaySection(force: Bool = true) async {
        guard !footballLiveAndNextDaySection.isLoading else { return }

        let now = fixedSecondNow()
        let needsRefresh = force
            || !footballLiveAndNextDaySection.hasLoaded
            || lastFootballMenuRefreshDate == nil
            || now.timeIntervalSince(lastFootballMenuRefreshDate!) >= Self.footballMenuRefreshInterval
        guard needsRefresh else { return }
        lastFootballMenuRefreshDate = now

        let cachedMatches = Self.liveAndNextDayMatches(from: Array(footballMatchesByID.values), now: now)
        let hasCachedMatches = !cachedMatches.isEmpty

        let loadingSection = FootballMatchesOverviewSection(
            title: footballLiveAndNextDaySection.title,
            matches: hasCachedMatches ? cachedMatches : footballLiveAndNextDaySection.matches,
            errorMessage: nil,
            isLoading: true,
            hasLoaded: footballLiveAndNextDaySection.hasLoaded || hasCachedMatches
        )
        if footballLiveAndNextDaySection != loadingSection {
            footballLiveAndNextDaySection = loadingSection
        }

        let limitedPresets = FootballCompetitionPreset.menuPresets.map {
            FootballCompetitionPreset(
                slug: $0.slug,
                title: $0.title,
                lookbackDays: 1,
                lookaheadDays: 1,
                category: $0.category,
                region: $0.region
            )
        }

        do {
            let fetchedMatches = try await footballClient.fetchMatches(for: limitedPresets)
            let refreshedMatches = await footballClient.refreshStatusesIfNeeded(for: fetchedMatches)
            let resolvedMatches = matchesPreservingKnownTimingContext(refreshedMatches)
            await cacheFootballMatches(resolvedMatches)
            let filteredMatches = Self.liveAndNextDayMatches(
                from: Self.resolvedFootballSectionMatches(
                    resolvedMatches,
                    cachedMatchesByID: footballMatchesByID,
                    now: now
                ),
                now: now
            )

            let loadedSection = FootballMatchesOverviewSection(
                title: footballLiveAndNextDaySection.title,
                matches: filteredMatches,
                errorMessage: nil,
                isLoading: false,
                hasLoaded: true
            )
            if footballLiveAndNextDaySection != loadedSection {
                footballLiveAndNextDaySection = loadedSection
            }
        } catch {
            let failedSection = FootballMatchesOverviewSection(
                title: footballLiveAndNextDaySection.title,
                matches: hasCachedMatches ? cachedMatches : footballLiveAndNextDaySection.matches,
                errorMessage: footballLiveAndNextDaySection.hasLoaded || hasCachedMatches
                    ? "Could not refresh live or next-24-hour fixtures right now. Showing cached matches."
                    : "Could not load live or next-24-hour fixtures right now.",
                isLoading: false,
                hasLoaded: footballLiveAndNextDaySection.hasLoaded || hasCachedMatches
            )
            if footballLiveAndNextDaySection != failedSection {
                footballLiveAndNextDaySection = failedSection
            }
        }
    }

    func syncManagedFootballEventsIfNeeded(now: Date, force: Bool = false) async {
        guard hasEventsAccess else {
            if !managedFootballMatchIDs.isEmpty {
                managedFootballMatchIDs = []
            }
            if !managedFootballMatches.isEmpty {
                managedFootballMatches = []
            }
            return
        }

        if shouldRunFootballLegacyMigration(now: now, force: force) {
            migrateLegacyManagedFootballEventsIfNeeded(now: now)
            lastFootballLegacyMigrationDate = now
        }
        if shouldRunFootballManagedRecovery(now: now, force: force) {
            await recoverManagedFootballEventRecordsIfNeeded(now: now)
            lastFootballManagedRecoveryDate = now
        }
        didFootballEventStoreChange = false

        let needsCleanup = force
            || lastFootballManagedCleanupDate == nil
            || now.timeIntervalSince(lastFootballManagedCleanupDate!) >= Self.footballManagedCleanupInterval
        if needsCleanup {
            _ = removeManagedFootballEventsOutsideSuggestionWindow(now: now)
            lastFootballManagedCleanupDate = now
        }

        let trackedEvents = trackedFootballSnapshotsByRefreshingState(now: now)
        applyManagedFootballAlertConfigurationIfNeeded(to: trackedEvents)

        guard !trackedEvents.isEmpty else {
            if !managedFootballMatches.isEmpty {
                managedFootballMatches = []
            }
            return
        }

        let needsNetworkRefresh = force
            || lastFootballManagedSyncDate == nil
            || now.timeIntervalSince(lastFootballManagedSyncDate!) >= Self.footballManagedSyncInterval
            || trackedEvents.contains { footballMatchesByID[$0.reference.matchID] == nil }

        guard needsNetworkRefresh else { return }

        let trackedPresets = deduplicatedFootballPresets(from: trackedEvents.map(\.reference.competitionSlug))
        do {
            let matches = try await footballClient.fetchMatches(for: trackedPresets)
            let refreshedMatches = await footballClient.refreshStatusesIfNeeded(for: matches)
            let resolvedMatches = matchesPreservingKnownTimingContext(refreshedMatches)
            await cacheFootballMatches(resolvedMatches)
            updateManagedFootballMatches(using: trackedEvents, now: now)
            await applyFootballEventUpdates(trackedEvents, using: resolvedMatches)
            lastFootballManagedSyncDate = now
        } catch {
            return
        }
    }

    func applyManagedFootballAlertConfigurationIfNeeded(now: Date) {
        guard hasEventsAccess else { return }
        let trackedEvents = trackedFootballSnapshotsByRefreshingState(now: now)
        applyManagedFootballAlertConfigurationIfNeeded(to: trackedEvents)
    }

}
