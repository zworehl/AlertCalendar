import AppKit
import Combine
import SwiftUI

extension SettingsFootballFixturesSectionView {
    func applyFootballCalendarAlertPreference() {
        let now = Self.minuteReferenceDate(for: AlertCalendarClock.nowRoundedToSecond())
        visibleNow = now
        refreshManagedMatchesDerivedState(now: now)
        monitor.applyManagedFootballAlertConfigurationIfNeeded(now: now)
        monitor.refreshManagedFootballTrackingSnapshot(now: now)
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
        guard let section = selectedCompetitionSection else { return }
        await monitor.loadFootballCompetitionSection(section.competition, force: true)
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
            let delay = max(0.25, nextRefresh.timeIntervalSince(now))
            let delayNanoseconds = UInt64(delay * 1_000_000_000)

            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }

            let refreshedNow = Self.minuteReferenceDate(for: AlertCalendarClock.nowRoundedToSecond())
            await MainActor.run {
                visibleNow = refreshedNow
                refreshManagedMatchesDerivedState(now: refreshedNow)
            }

            if browseMode == .liveAndNextDay {
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
        competitionSectionsByRegionCache = FootballCompetitionRegion.allCases.compactMap { region in
            let sections = footballMenuSections.filter { $0.competition.region == region }
            guard !sections.isEmpty else { return nil }
            return (region, sections)
        }
        competitionSectionsWithErrorsCache = footballMenuSections.filter { $0.errorMessage != nil }
        hasAnyCompetitionCardsCache = footballMenuSections.contains { !displayedMatches($0.matches).isEmpty }
        hasAttemptedCompetitionLoadsCache = footballMenuSections.contains {
            $0.hasLoaded || $0.isLoading || $0.errorMessage != nil
        }
        synchronizeCompetitionSelection()
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
        let now = visibleNow
        let lookbackStart = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -normalizedFinishedMatchLookbackDays, to: now)
            ?? now.addingTimeInterval(-Double(normalizedFinishedMatchLookbackDays) * 24 * 60 * 60)
        let lookaheadEnd = Calendar.autoupdatingCurrent.date(byAdding: .day, value: normalizedMatchLookaheadDays, to: now)
            ?? now.addingTimeInterval(Double(normalizedMatchLookaheadDays) * 24 * 60 * 60)

        return matches.filter { match in
            if match.statusState == .inProgress {
                return true
            }

            if match.statusState == .finished {
                guard showFinishedFootballMatches else { return false }
                return CalendarMonitor.shouldDisplayFinishedFootballMatch(
                    match,
                    now: now,
                    lookbackDays: normalizedFinishedMatchLookbackDays
                )
            }

            if match.statusReliability == .awaitingLiveData || match.statusReliability == .delayedLiveData {
                return true
            }

            return match.startDate >= lookbackStart && match.startDate <= lookaheadEnd
        }
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

        let availableCompetitionIDs = Set(regionEntry.sections.map(\.id))
        guard availableCompetitionIDs.contains(selectedCompetitionID ?? "") else {
            selectedCompetitionID = regionEntry.sections.first?.id
            return
        }
    }

    static func normalizedFootballWindowDays(_ value: Int) -> Int {
        AppSettingsRules.normalizedFootballWindowDays(value)
    }

    static func matchWindowValueText(days: Int) -> String {
        SettingsView.durationValueText(value: normalizedFootballWindowDays(days), singular: "day", plural: "days")
    }
}
