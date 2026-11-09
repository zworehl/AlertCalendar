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
    nonisolated static let footballMenuRefreshInterval: TimeInterval = 15 * 60
    nonisolated static let footballManagedSyncInterval: TimeInterval = 60
    nonisolated static let footballActiveRefreshInterval: TimeInterval = 30
    nonisolated static let footballApproachingRefreshInterval: TimeInterval = 5 * 60
    nonisolated static let footballMissingCacheRefreshInterval: TimeInterval = 5 * 60
    nonisolated static let footballUpcomingRefreshInterval: TimeInterval = 15 * 60
    nonisolated static let footballIdleRefreshInterval: TimeInterval = 3 * 60 * 60
    nonisolated static let footballApproachingKickoffWindow: TimeInterval = 60 * 60
    nonisolated static let footballKickoffGraceWindow: TimeInterval = 15 * 60
    nonisolated static let footballPostMatchStabilizationWindow: TimeInterval = 10 * 60
    nonisolated static let footballSettledRefreshInterval = TimeInterval.greatestFiniteMagnitude
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
    nonisolated static let footballLiveShortTailDuration: TimeInterval = 5 * 60
    nonisolated static let footballLiveLateTailDuration: TimeInterval = 2 * 60
    nonisolated static let footballLiveEndDateRoundingInterval: TimeInterval = 5 * 60
    nonisolated static let footballHalfTimeBreakDuration: TimeInterval = 15 * 60
    nonisolated static let footballPenaltyShootoutEstimateDuration: TimeInterval = 15 * 60
    nonisolated static let footballPenaltyShootoutInferenceMinute = 124
    nonisolated static let footballEstimatedEndMarginDuration: TimeInterval = 5 * 60
    nonisolated static let footballManagedEventMatchingTolerance: TimeInterval = 5 * 60
    nonisolated static let footballStructuredLocationToleranceMeters: CLLocationDistance = 150

    func refreshFootballDataIfNeeded(
        now: Date,
        force: Bool = false,
        reason: CalendarMonitorRefreshReason = .manual,
        syncManagedEvents: Bool? = nil,
        syncAutoAdd: Bool? = nil
    ) async {
        let shouldSyncManagedEvents = force || (syncManagedEvents ?? reason.triggersManagedFootballSync)
        if shouldSyncManagedEvents {
            CalendarMonitorLog.football.debug("Checking managed football sync for refresh reason: \(reason.rawValue, privacy: .public)")
            await syncManagedFootballEventsIfNeeded(now: now, force: force)
        } else {
            CalendarMonitorLog.football.debug("Skipped managed football sync for refresh reason: \(reason.rawValue, privacy: .public)")
        }

        if force || (syncAutoAdd ?? reason.triggersFootballAutoAddSync) {
            await syncAutoAddedFootballMatchesIfNeeded(now: now, force: force)
        }
        if force {
            await refreshLastFootballCompetitionAvailability(force: true)
            for section in footballMenuSections where footballState.detailedCompetitionSlugs.contains(section.competition.slug) {
                await loadFootballCompetitionSection(section.competition, force: true)
            }
            if footballLiveAndNextDaySection.hasLoaded || footballLiveAndNextDaySection.errorMessage != nil {
                await loadFootballLiveAndNextDaySection(force: true)
            }
        }
    }

    func invalidateManagedFootballSnapshotCache(markEventStoreChanged: Bool = false) {
        cachedManagedFootballSnapshots = []
        isManagedFootballSnapshotCacheValid = false
        if markEventStoreChanged {
            didFootballEventStoreChange = true
        }
    }

    func shouldRefreshFootballOnHeartbeat(now: Date) -> Bool {
        if footballState.autoAddRefreshFailed, !footballAutoAddCompetitionSlugs().isEmpty,
           CalendarMonitorTime.hasElapsed(since: lastFootballAutoAddRefreshDate, now: now, interval: 60) { return true }
        guard !managedFootballMatchIDs.isEmpty else { return false }
        let tracked = managedFootballMatchIDs.compactMap { footballMatchesByID[$0] }
        let interval = footballState.managedRefreshFailed ? 60 : Self.footballManagedRefreshInterval(
            for: tracked, hasMissingTrackedMatches: tracked.count < managedFootballMatchIDs.count, now: now
        )
        return CalendarMonitorTime.hasElapsed(since: lastFootballManagedSyncDate, now: now, interval: interval)
    }

    func shouldRunFootballLegacyMigration(now: Date, force: Bool) -> Bool {
        force
            || didFootballEventStoreChange
            || CalendarMonitorTime.hasElapsed(since: lastFootballLegacyMigrationDate, now: now, interval: Self.footballLegacyMigrationInterval)
    }

    func shouldRunFootballManagedRecovery(now: Date, force: Bool) -> Bool {
        force
            || didFootballEventStoreChange
            || managedFootballEventRecords.isEmpty
            || CalendarMonitorTime.hasElapsed(since: lastFootballManagedRecoveryDate, now: now, interval: Self.footballManagedRecoveryInterval)
    }

    func ensureFootballCompetitionSections() {
        let existingSectionsByID = Dictionary(uniqueKeysWithValues: footballMenuSections.map { ($0.id, $0) })
        let nextSections = FootballCompetitionPreset.menuPresets.map { preset in
            if let section = existingSectionsByID[preset.id] { return section }
            if let cached = footballState.availabilityBySlug[preset.slug] {
                return FootballMenuCompetitionSection(
                    competition: preset, matches: cached.matches, errorMessage: nil, isLoading: false,
                    hasLoaded: true, checkedWindow: cached.window
                )
            }
            return Self.defaultFootballCompetitionSection(for: preset)
        }
        guard footballMenuSections != nextSections else { return }
        footballMenuSections = nextSections
    }

    func loadFootballCompetitionSection(_ competition: FootballCompetitionPreset, force: Bool = true) async {
        await restorePersistentCachesIfNeeded()
        ensureFootballCompetitionSections()
        guard let existingSection = footballMenuSections.first(where: { $0.id == competition.id }) else { return }
        guard !existingSection.isLoading else { return }
        let now = fixedSecondNow()
        let needsDetailRefresh = footballState.detailedCompetitionLoadDates[competition.slug].map {
            now.timeIntervalSince($0) >= Self.footballMenuRefreshInterval
        } ?? true
        guard force || !existingSection.hasLoaded || existingSection.errorMessage != nil
            || needsDetailRefresh
            || dataRefreshIssues.contains(where: { $0.id == "football.browse.\(competition.slug)" }) else { return }
        footballState.detailedCompetitionSlugs.insert(competition.slug)

        let cachedMatches = FootballFixtureLoadResult(
            matches: cachedCompetitionMatches(for: competition, now: now) + existingSection.matches
        ).restoringCachedMatches([])
        let hasCachedMatches = !cachedMatches.isEmpty

        updateFootballCompetitionSection(competition.id) { currentSection in
            FootballMenuCompetitionSection(
                competition: currentSection.competition,
                matches: hasCachedMatches ? cachedMatches : currentSection.matches,
                errorMessage: currentSection.errorMessage,
                isLoading: true,
                hasLoaded: currentSection.hasLoaded || hasCachedMatches,
                checkedWindow: currentSection.checkedWindow
            )
        }

        let checkedWindow = FootballCompetitionAvailabilityWindow(
            now: now, lookbackDays: competition.lookbackDays, lookaheadDays: competition.lookaheadDays
        )
        let ranges = FootballDataAPIClient.scoreboardDateRanges(
            start: checkedWindow.start, end: checkedWindow.end, calendar: .autoupdatingCurrent
        ).map { FootballScoreboardDateRange(start: $0.0, end: $0.1) }
        do {
            let result = try await footballClient.fetchFixtureLoadResult(
                for: [competition],
                dateRangesByCompetitionSlug: [competition.slug: ranges],
                forceRefresh: force
            )
            let fetchedMatches = result.restoringCachedMatches(cachedMatches)
            let refreshedMatches = await footballClient.refreshStatusesIfNeeded(for: fetchedMatches, forceRefresh: force)
            let resolvedMatches = matchesPreservingKnownTimingContext(refreshedMatches)
            await cacheFootballMatches(resolvedMatches)
            if result.failures.isEmpty { markFootballRefreshed(at: now) }
            let matches = Self.resolvedFootballSectionMatches(
                resolvedMatches,
                cachedMatchesByID: footballMatchesByID,
                now: now
            )
            if result.failures.isEmpty && result.availablePageCount > 0 {
                footballState.detailedCompetitionLoadDates[competition.slug] = now
                footballState.availabilityBySlug[competition.slug] = FootballCompetitionAvailability(
                    competitionSlug: competition.slug, fetchedAt: now, window: checkedWindow, matches: matches
                )
                await persistFootballCompetitionAvailability()
            }

            updateFootballCompetitionSection(competition.id) { _ in
                FootballMenuCompetitionSection(
                    competition: competition,
                    matches: matches,
                    errorMessage: result.warning,
                    isLoading: false,
                    hasLoaded: result.availablePageCount > 0 || !matches.isEmpty,
                    checkedWindow: checkedWindow
                )
            }
            if result.failures.isEmpty {
                await ExternalFeedMetrics.shared.recordAppliedData(source: "football.snapshot", at: now)
            }
            await autoAddFootballMatches(matches, now: now)
        } catch is CancellationError {
            updateFootballCompetitionSection(competition.id) { section in
                FootballMenuCompetitionSection(
                    competition: competition, matches: section.matches, errorMessage: existingSection.errorMessage,
                    isLoading: false, hasLoaded: existingSection.hasLoaded, checkedWindow: existingSection.checkedWindow
                )
            }
        } catch {
            updateFootballCompetitionSection(competition.id) { currentSection in
                FootballMenuCompetitionSection(
                    competition: currentSection.competition,
                    matches: currentSection.matches,
                    errorMessage: FootballDataAPIClient.fixtureFailureDescription(error),
                    isLoading: false,
                    hasLoaded: currentSection.hasLoaded,
                    checkedWindow: currentSection.checkedWindow
                )
            }
        }
    }

    func loadFootballLiveAndNextDaySection(force: Bool = true) async {
        guard !footballLiveAndNextDaySection.isLoading else { return }

        let now = fixedSecondNow()
        let cachedMatches = Self.liveAndNextDayMatches(from: Array(footballMatchesByID.values), now: now)
        let menuRefreshInterval = footballLiveAndNextDaySection.errorMessage == nil
            ? Self.footballRefreshInterval(for: cachedMatches, now: now) : 60
        let needsRefresh = force
            || !footballLiveAndNextDaySection.hasLoaded
            || CalendarMonitorTime.hasElapsed(since: lastFootballMenuRefreshDate, now: now, interval: menuRefreshInterval)
        guard needsRefresh else { return }
        lastFootballMenuRefreshDate = now

        let hasCachedMatches = !cachedMatches.isEmpty

        let loadingSection = FootballMatchesOverviewSection(
            title: footballLiveAndNextDaySection.title,
            matches: hasCachedMatches ? cachedMatches : footballLiveAndNextDaySection.matches,
            errorMessage: footballLiveAndNextDaySection.errorMessage,
            isLoading: true,
            hasLoaded: footballLiveAndNextDaySection.hasLoaded || hasCachedMatches
        )
        if footballLiveAndNextDaySection != loadingSection {
            footballLiveAndNextDaySection = loadingSection
        }

        let limitedPresets = FootballCompetitionPreset.menuPresets
        let calendar = Calendar(identifier: .gregorian)
        let dayStart = calendar.startOfDay(for: now)
        let range = FootballScoreboardDateRange(
            start: calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart,
            end: calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        )
        let rangesBySlug = Dictionary(
            uniqueKeysWithValues: limitedPresets.map { ($0.slug, [range]) }
        )

        do {
            let result = try await footballClient.fetchFixtureLoadResult(
                for: limitedPresets,
                dateRangesByCompetitionSlug: rangesBySlug,
                enrichTeams: false,
                forceRefresh: force,
                healthScope: "live"
            )
            let refreshedMatches = await footballClient.refreshStatusesIfNeeded(
                for: result.restoringCachedMatches(cachedMatches), forceRefresh: force
            )
            let resolvedMatches = matchesPreservingKnownTimingContext(refreshedMatches)
            await cacheFootballMatches(resolvedMatches)
            if result.failures.isEmpty { markFootballRefreshed(at: now) }
            let resolvedLiveCandidates = resolvedMatches.map { footballMatchesByID[$0.id] ?? $0 }
            let filteredMatches = Self.liveAndNextDayMatches(
                from: resolvedLiveCandidates,
                now: now
            )

            let loadedSection = FootballMatchesOverviewSection(
                title: footballLiveAndNextDaySection.title,
                matches: filteredMatches,
                errorMessage: result.warning,
                isLoading: false,
                hasLoaded: result.availablePageCount > 0 || !filteredMatches.isEmpty
            )
            if footballLiveAndNextDaySection != loadedSection {
                footballLiveAndNextDaySection = loadedSection
            }
            if result.failures.isEmpty {
                await ExternalFeedMetrics.shared.recordAppliedData(source: "football.snapshot", at: now)
            }
            await autoAddFootballMatches(resolvedMatches, now: now)
        } catch {
            let failedSection = FootballMatchesOverviewSection(
                title: footballLiveAndNextDaySection.title,
                matches: hasCachedMatches ? cachedMatches : footballLiveAndNextDaySection.matches,
                errorMessage: FootballDataAPIClient.fixtureFailureDescription(error),
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
            if migrateLegacyManagedFootballEventsIfNeeded(now: now) {
                lastFootballLegacyMigrationDate = now
            }
        }
        if shouldRunFootballManagedRecovery(now: now, force: force) {
            await recoverManagedFootballEventRecordsIfNeeded(
                now: now,
                forceRefresh: force
            )
            lastFootballManagedRecoveryDate = now
        }
        didFootballEventStoreChange = false

        let needsCleanup = force
            || CalendarMonitorTime.hasElapsed(since: lastFootballManagedCleanupDate, now: now, interval: Self.footballManagedCleanupInterval)
        if needsCleanup, performManagedFootballCleanup(now: now) != nil {
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

        let trackedMatches = trackedEvents.compactMap { footballMatchesByID[$0.reference.matchID] }
        let hasMissingTrackedMatches = trackedMatches.count < trackedEvents.count
        let managedSyncInterval = footballState.managedRefreshFailed ? 60 : Self.footballManagedRefreshInterval(
            for: trackedMatches,
            hasMissingTrackedMatches: hasMissingTrackedMatches,
            now: now
        )
        let needsNetworkRefresh = force
            || CalendarMonitorTime.hasElapsed(since: lastFootballManagedSyncDate, now: now, interval: managedSyncInterval)

        guard needsNetworkRefresh else { return }

        let trackedPresets = deduplicatedFootballPresets(from: trackedEvents.map(\.reference.competitionSlug))
        lastFootballManagedSyncDate = now
        do {
            let rangesBySlug = footballScoreboardDateRangesByCompetition(
                trackedEvents.map { ($0.reference.competitionSlug, $0.event.startDate) }
            )
            let result = try await footballClient.fetchFixtureLoadResult(
                for: trackedPresets,
                dateRangesByCompetitionSlug: rangesBySlug,
                forceRefresh: force,
                healthScope: "tracked"
            )
            footballState.managedRefreshFailed = !result.failures.isEmpty
            let matches = result.restoringCachedMatches(trackedMatches)
            let forceSummaryMatchIDs = Self.footballManagedMatchIDsNeedingActualEndBackfill(
                matches,
                trackedMatchIDs: Set(trackedEvents.map(\.reference.matchID)),
                cachedMatchesByID: footballMatchesByID
            ).union(Self.footballManagedMatchIDsNeedingVenueBackfill(
                matches,
                trackedMatchIDs: Set(trackedEvents.map(\.reference.matchID)),
                cachedMatchesByID: footballMatchesByID
            ))
            let refreshedMatches = await footballClient.refreshStatusesIfNeeded(
                for: matches,
                forceSummaryForMatchIDs: forceSummaryMatchIDs,
                forceRefresh: force
            )
            let resolvedMatches = matchesPreservingKnownTimingContext(refreshedMatches)
            await cacheFootballMatches(resolvedMatches)
            if result.failures.isEmpty { markFootballRefreshed(at: now) }
            updateManagedFootballMatches(using: trackedEvents, now: now)
            await applyFootballEventUpdates(trackedEvents, using: resolvedMatches)
            lastFootballManagedSyncDate = now
        } catch {
            if !(error is CancellationError) { footballState.managedRefreshFailed = true }
            return
        }
    }

    func footballScoreboardDateRangesByCompetition(
        _ entries: [(competitionSlug: String, date: Date)]
    ) -> [String: [FootballScoreboardDateRange]] {
        let calendar = Calendar(identifier: .gregorian)
        return Dictionary(grouping: entries, by: \.competitionSlug).mapValues { groupedEntries in
            let days = Array(Set(groupedEntries.flatMap { entry -> [Date] in
                let day = calendar.startOfDay(for: entry.date)
                return (-1...1).compactMap { calendar.date(byAdding: .day, value: $0, to: day) }
            })).sorted()
            guard let first = days.first else { return [] }

            var ranges: [FootballScoreboardDateRange] = []
            var start = first
            var end = first
            for day in days.dropFirst() {
                let nextDay = calendar.date(byAdding: .day, value: 1, to: end) ?? end
                if day <= nextDay {
                    end = day
                } else {
                    ranges.append(FootballScoreboardDateRange(start: start, end: end))
                    start = day
                    end = day
                }
            }
            ranges.append(FootballScoreboardDateRange(start: start, end: end))
            return ranges
        }
    }

    func applyManagedFootballAlertConfigurationIfNeeded(now: Date) {
        guard hasEventsAccess else { return }
        let trackedEvents = trackedFootballSnapshotsByRefreshingState(now: now)
        applyManagedFootballAlertConfigurationIfNeeded(to: trackedEvents)
    }

}
