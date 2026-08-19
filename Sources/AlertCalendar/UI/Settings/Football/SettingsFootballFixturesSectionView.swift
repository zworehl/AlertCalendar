import AppKit
import Combine
import SwiftUI

struct SettingsFootballFixturesSectionView: View {
    enum FootballBrowseMode: String, CaseIterable, Identifiable {
        case competitions = "Competitions"
        case liveAndNextDay = "Now + Next 24h"
        case addedMatches = "Added Matches"

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .competitions:
                return "trophy"
            case .liveAndNextDay:
                return "clock"
            case .addedMatches:
                return "calendar.badge.checkmark"
            }
        }
    }

    nonisolated static let preferredMatchCardWidth: CGFloat = 306
    nonisolated static let minimumMatchCardWidth: CGFloat = 272
    nonisolated static let topMenuControlWidth: CGFloat = 320
    nonisolated static let topShowControlWidth: CGFloat = 500
    nonisolated static let competitionColumnSpacing: CGFloat = 16
    nonisolated static let competitionSidebarWidth: CGFloat = 320
    nonisolated static let matchActionSlotWidth: CGFloat = 112
    nonisolated static let minimumMatchListViewportHeight: CGFloat = 120
    nonisolated static let maximumMatchListViewportHeight: CGFloat = 1_200
    static let minimumFootballWindowDays = AppSettingsRules.minimumFootballWindowDays
    static let maximumFootballWindowDays = AppSettingsRules.maximumFootballWindowDays

    let monitor: CalendarMonitor

    @Binding var footballTargetCalendarID: String
    @Binding var autoAddFootballCompetitionSlugs: Set<String>
    @Binding var footballCalendarAlertOption: FootballCalendarAlertOption
    @Binding var enableFootballGoalNotifications: Bool
    @Binding var enableFootballDisallowedGoalNotifications: Bool
    @Binding var includeFootballGoalScorerInNotifications: Bool
    @Binding var enableFootballFinalNotifications: Bool
    @Binding var enableFootballAutoAddNotifications: Bool
    @Binding var showFinishedFootballMatches: Bool
    @Binding var finishedFootballMatchLookbackDays: Int
    @Binding var footballMatchLookaheadDays: Int
    @Binding var pendingCalendarChanges: [String: SettingsPendingItemChange<FootballFixtureMatch>]
    @State var browseMode: FootballBrowseMode = .competitions
    @State var selectedCompetitionRegionID: String?
    @State var selectedCompetitionID: String?
    @State var isRefreshingManagedMatches = false
    @State var visibleNow = AlertCalendarClock.nowRoundedToSecond()
    @State var hasEventsAccess = false
    @State var availableEventCalendars: [AvailableCalendar] = []
    @State var writableEventCalendars: [AvailableCalendar] = []
    @State var footballMenuSections: [FootballMenuCompetitionSection] = []
    @State var footballLiveAndNextDaySection = FootballMatchesOverviewSection.placeholder(title: "Now & Next 24 Hours")
    @State var managedFootballMatchIDs: Set<String> = []
    @State var managedFootballMatches: [FootballFixtureMatch] = []
    @State var competitionSectionsByRegionCache: [(region: FootballCompetitionRegion, sections: [FootballMenuCompetitionSection])] = []
    @State var competitionSectionsWithErrorsCache: [FootballMenuCompetitionSection] = []
    @State var hasAnyCompetitionCardsCache = false
    @State var hasAttemptedCompetitionLoadsCache = false
    @State var liveAndNextDayMatchesByRegionCache: [(region: FootballCompetitionRegion, matches: [FootballFixtureMatch])] = []
    @State var upcomingManagedMatchesCache: [FootballFixtureMatch] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !hasEventsAccess {
                emptyState("Grant Calendar access to add football fixtures.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if writableCalendars.isEmpty {
                emptyState("No writable event calendars are available.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                footballContentSection
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            visibleNow = Self.minuteReferenceDate(for: AlertCalendarClock.nowRoundedToSecond())
            finishedFootballMatchLookbackDays = Self.normalizedFootballWindowDays(finishedFootballMatchLookbackDays)
            footballMatchLookaheadDays = Self.normalizedFootballWindowDays(footballMatchLookaheadDays)
            monitor.ensureFootballCompetitionSections()
            monitor.refreshManagedFootballTrackingSnapshot(now: visibleNow)
            synchronizeViewStateFromMonitor()
        }
        .task(id: browseMode) {
            switch browseMode {
            case .competitions:
                await loadSelectedCompetitionIfNeeded()
            case .liveAndNextDay:
                await monitor.loadFootballLiveAndNextDaySection(force: false)
            case .addedMatches:
                return
            }
        }
        .task(id: selectedCompetitionID) {
            guard browseMode == .competitions else { return }
            await loadSelectedCompetitionIfNeeded()
        }
        .task {
            await refreshManagedMatchesPanel(now: visibleNow, force: true)
        }
        .task {
            await runVisibleRefreshLoop()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            let now = Self.minuteReferenceDate(for: AlertCalendarClock.nowRoundedToSecond())
            visibleNow = now
            refreshManagedMatchesDerivedState(now: now)
            Task {
                if browseMode == .liveAndNextDay {
                    await monitor.loadFootballLiveAndNextDaySection(force: false)
                }
                if shouldRefreshManagedMatchesOnVisibleTick {
                    await refreshManagedMatchesPanel(now: now)
                }
            }
        }
        .onChange(of: showFinishedFootballMatches) { _ in
            refreshCompetitionSectionsDerivedState()
            refreshLiveAndNextDayDerivedState()
        }
        .onChange(of: finishedFootballMatchLookbackDays) { newValue in
            let normalizedValue = Self.normalizedFootballWindowDays(newValue)
            if normalizedValue != newValue {
                finishedFootballMatchLookbackDays = normalizedValue
                return
            }

            refreshCompetitionSectionsDerivedState()
            refreshLiveAndNextDayDerivedState()
        }
        .onChange(of: footballMatchLookaheadDays) { newValue in
            let normalizedValue = Self.normalizedFootballWindowDays(newValue)
            if normalizedValue != newValue {
                footballMatchLookaheadDays = normalizedValue
                return
            }

            refreshCompetitionSectionsDerivedState()
            refreshLiveAndNextDayDerivedState()
        }
        .onReceive(monitor.$hasEventsAccess.removeDuplicates()) { value in
            guard hasEventsAccess != value else { return }
            hasEventsAccess = value
            refreshWritableCalendars()
        }
        .onReceive(monitor.$availableEventCalendars.removeDuplicates()) { calendars in
            guard availableEventCalendars != calendars else { return }
            availableEventCalendars = calendars
            refreshWritableCalendars()
        }
        .onReceive(monitor.$footballMenuSections.removeDuplicates()) { sections in
            guard footballMenuSections != sections else { return }
            footballMenuSections = sections
            refreshCompetitionSectionsDerivedState()
        }
        .onReceive(monitor.$footballLiveAndNextDaySection.removeDuplicates()) { section in
            guard footballLiveAndNextDaySection != section else { return }
            footballLiveAndNextDaySection = section
            refreshLiveAndNextDayDerivedState()
        }
        .onReceive(monitor.$managedFootballMatchIDs.removeDuplicates()) { ids in
            guard managedFootballMatchIDs != ids else { return }
            managedFootballMatchIDs = ids
        }
        .onReceive(monitor.$managedFootballMatches.removeDuplicates()) { matches in
            guard managedFootballMatches != matches else { return }
            managedFootballMatches = matches
            refreshManagedMatchesDerivedState(now: visibleNow)
        }
    }

}
