import AppKit
import Combine
import SwiftUI

extension SettingsFootballFixturesSectionView {
    var hasUnresolvedCompetitionLoads: Bool {
        let window = FootballCompetitionAvailabilityWindow(
            now: visibleNow, lookbackDays: normalizedFinishedMatchLookbackDays, lookaheadDays: normalizedMatchLookaheadDays
        )
        return footballMenuSections.contains {
            $0.errorMessage == nil && (!$0.hasLoaded || $0.isLoading || $0.checkedWindow?.contains(window) == false)
        }
    }

    func refreshCompetitionAvailability(force: Bool = false) async {
        await monitor.refreshFootballCompetitionAvailability(
            lookbackDays: normalizedFinishedMatchLookbackDays,
            lookaheadDays: normalizedMatchLookaheadDays,
            force: force
        )
    }

    var shouldRefreshManagedMatchesOnVisibleTick: Bool {
        !managedFootballMatchIDs.isEmpty || !managedFootballMatches.isEmpty
    }

    func synchronizeViewStateFromMonitor() {
        hasEventsAccess = monitor.hasEventsAccess
        availableEventCalendars = monitor.availableEventCalendars
        footballMenuSections = monitor.footballMenuSections
        footballLiveAndNextDaySection = monitor.footballLiveAndNextDaySection
        managedFootballMatchIDs = monitor.managedFootballMatchIDs
        managedFootballMatches = monitor.managedFootballMatches
        refreshCompetitionSectionsDerivedState()
        refreshLiveAndNextDayDerivedState()
        refreshManagedMatchesDerivedState(now: visibleNow)
        refreshWritableCalendars()
    }

    func refreshWritableCalendars() {
        let nextCalendars = hasEventsAccess ? monitor.writableFootballTargetCalendars() : []
        guard writableEventCalendars != nextCalendars else { return }
        writableEventCalendars = nextCalendars
    }

    func loadCompetitionFixtures(_ section: FootballMenuCompetitionSection) async {
        await monitor.loadFootballCompetitionSection(section.competition, force: true)
    }

    func loadSelectedCompetitionIfNeeded() async {
        guard !Task.isCancelled, browseMode == .competitions else { return }
        guard let section = selectedCompetitionSection else { return }
        await monitor.loadFootballCompetitionSection(section.competition, force: false)
    }

    func retryFailedCompetitionLoads() async {
        let sectionsToRetry = competitionSectionsWithErrors.isEmpty
            ? (selectedCompetitionSection.map { [$0] } ?? [])
            : competitionSectionsWithErrors
        for section in sectionsToRetry {
            await loadCompetitionFixtures(section)
        }
    }

    func retryLiveAndNextDayLoad() async {
        await monitor.loadFootballLiveAndNextDaySection(force: true)
    }

    func runVisibleRefreshLoop() async {
        while !Task.isCancelled {
            let now = AlertCalendarClock.nowRoundedToSecond()
            let nextRefresh = Self.nextMinuteBoundary(after: now)
            let delayNanoseconds = CalendarMonitorTime.nanoseconds(
                until: nextRefresh,
                now: now,
                minimumDelay: 0.25
            )

            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }

            let refreshedNow = Self.minuteReferenceDate(for: AlertCalendarClock.nowRoundedToSecond())
            await MainActor.run {
                visibleNow = refreshedNow
                refreshCompetitionSectionsDerivedState()
                refreshManagedMatchesDerivedState(now: refreshedNow)
            }

            if browseMode == .competitions {
                await refreshCompetitionAvailability()
            } else if browseMode == .liveAndNextDay {
                await monitor.loadFootballLiveAndNextDaySection(force: false)
            }
            if shouldRefreshManagedMatchesOnVisibleTick {
                await refreshManagedMatchesPanel(now: refreshedNow)
            }
        }
    }

    @MainActor
    func refreshManagedMatchesPanel(now: Date, force: Bool = false) async {
        guard !force || shouldRefreshManagedMatchesOnVisibleTick || !monitor.managedFootballEventRecords.isEmpty else {
            return
        }
        guard force || shouldRefreshManagedMatchesOnVisibleTick else { return }
        isRefreshingManagedMatches = true
        defer { isRefreshingManagedMatches = false }
        await monitor.syncManagedFootballEventsIfNeeded(now: now, force: force)
    }

    func refreshCompetitionSectionsDerivedState() {
        competitionSectionsByRegionCache = Self.browsableCompetitionSectionsByRegion(
            from: footballMenuSections, now: visibleNow, lookbackDays: normalizedFinishedMatchLookbackDays,
            lookaheadDays: normalizedMatchLookaheadDays, showFinishedMatches: showFinishedFootballMatches
        )
        competitionSectionsWithErrorsCache = footballMenuSections.filter { $0.errorMessage != nil }
        hasAnyCompetitionCardsCache = footballMenuSections.contains { !displayedMatches($0.matches).isEmpty }
        hasAttemptedCompetitionLoadsCache = footballMenuSections.contains {
            $0.hasLoaded || $0.isLoading || $0.errorMessage != nil
        }
        synchronizeCompetitionSelection()
    }

    nonisolated static func browsableCompetitionSectionsByRegion(
        from sections: [FootballMenuCompetitionSection],
        now: Date = AlertCalendarClock.nowRoundedToSecond(),
        lookbackDays: Int = FootballCompetitionPreset.suggestionWindowLookbackDays,
        lookaheadDays: Int = FootballCompetitionPreset.suggestionWindowLookaheadDays,
        showFinishedMatches: Bool = true
    ) -> [(region: FootballCompetitionRegion, sections: [FootballMenuCompetitionSection])] {
        let availableSections = sections.filter { section in
            // Unknown competitions are checked before becoming selectable. Failures stay retryable.
            if section.errorMessage != nil { return true }
            guard section.hasLoaded else { return false }
            return !displayedMatches(
                section.matches, now: now, lookbackDays: lookbackDays,
                lookaheadDays: lookaheadDays, showFinishedMatches: showFinishedMatches
            ).isEmpty
        }
        return FootballCompetitionRegion.allCases.compactMap { region in
            let regionalSections = availableSections.filter { $0.competition.region == region }
            guard !regionalSections.isEmpty else { return nil }
            return (region, regionalSections)
        }
    }

    func refreshLiveAndNextDayDerivedState() {
        let visibleMatches = displayedMatches(footballLiveAndNextDaySection.matches)
        let nextRegions = FootballCompetitionRegion.allCases.compactMap { region -> (region: FootballCompetitionRegion, matches: [FootballFixtureMatch])? in
            let matches = visibleMatches.filter { $0.competitionRegion == region }
            guard !matches.isEmpty else { return nil }
            guard matches.contains(where: { $0.statusState == .scheduled }) else { return nil }
            return (region, matches)
        }

        liveAndNextDayMatchesByRegionCache = nextRegions
    }

    func displayedMatches(_ matches: [FootballFixtureMatch]) -> [FootballFixtureMatch] {
        Self.displayedMatches(
            matches, now: visibleNow, lookbackDays: normalizedFinishedMatchLookbackDays,
            lookaheadDays: normalizedMatchLookaheadDays, showFinishedMatches: showFinishedFootballMatches
        )
    }

    nonisolated static func displayedMatches(
        _ matches: [FootballFixtureMatch], now: Date, lookbackDays: Int,
        lookaheadDays: Int, showFinishedMatches: Bool
    ) -> [FootballFixtureMatch] {
        let lookbackStart = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -lookbackDays, to: now)
            ?? now.addingTimeInterval(-Double(lookbackDays) * 24 * 60 * 60)
        let lookaheadEnd = Calendar.autoupdatingCurrent.date(byAdding: .day, value: lookaheadDays, to: now)
            ?? now.addingTimeInterval(Double(lookaheadDays) * 24 * 60 * 60)

        return Self.matchesEligibleForFootballCards(matches).filter { match in
            if match.statusState == .inProgress {
                return true
            }

            if match.statusState == .finished {
                guard showFinishedMatches else { return false }
                return CalendarMonitor.shouldDisplayFinishedFootballMatch(
                    match,
                    now: now,
                    lookbackDays: lookbackDays
                )
            }

            if match.statusReliability == .awaitingLiveData || match.statusReliability == .delayedLiveData {
                return true
            }

            return match.startDate >= lookbackStart && match.startDate <= lookaheadEnd
        }
    }

    nonisolated static func matchesEligibleForFootballCards(_ matches: [FootballFixtureMatch]) -> [FootballFixtureMatch] {
        matches.filter { !FootballFixtureFormatter.hasUnknownParticipants(in: $0) }
    }

    func refreshManagedMatchesDerivedState(now: Date) {
        let nextMatches = CalendarMonitor.upcomingManagedFootballMatches(
            from: managedFootballMatches,
            now: now
        )
        guard upcomingManagedMatchesCache != nextMatches else { return }
        upcomingManagedMatchesCache = nextMatches
    }

    func synchronizeCompetitionSelection() {
        guard let regionEntry = selectedCompetitionRegionEntry else {
            selectedCompetitionRegionID = nil
            selectedCompetitionID = nil
            return
        }

        if selectedCompetitionRegionID != regionEntry.region.id {
            selectedCompetitionRegionID = regionEntry.region.id
        }

        let preferredID = Self.preferredCompetitionID(in: regionEntry.sections, currentID: selectedCompetitionID)
        if selectedCompetitionID != preferredID { selectedCompetitionID = preferredID }
    }

    nonisolated static func preferredCompetitionID(
        in sections: [FootballMenuCompetitionSection], currentID: String?
    ) -> String? {
        if let currentID, sections.contains(where: { $0.id == currentID }) { return currentID }
        return sections.first?.id
    }

    static func normalizedFootballWindowDays(_ value: Int) -> Int {
        AppSettingsRules.normalizedFootballWindowDays(value)
    }

    static func matchWindowValueText(days: Int) -> String {
        SettingsView.durationValueText(value: normalizedFootballWindowDays(days), singular: L10n.text("day"), plural: L10n.text("days"))
    }
}
