import AppKit
import Combine
import SwiftUI

struct SettingsFootballFixturesSectionView: View {
    enum FootballBrowseMode: String, CaseIterable, Identifiable {
        case competitions = "Competitions"
        case liveAndNextDay = "Now + Next 24h"
        case addedMatches = "Added Matches"

        var id: String { rawValue }
    }

    static let scrollableMatchCardThreshold = 12
    static let preferredMatchCardWidth: CGFloat = 306
    static let minimumMatchCardWidth: CGFloat = 272
    static let inlineFieldLabelWidth: CGFloat = 96
    static let topMenuControlWidth: CGFloat = 320
    static let topShowControlWidth: CGFloat = 500
    static let matchActionButtonSize: CGFloat = 18
    static let matchActionSlotWidth: CGFloat = 112
    static let minimumFootballWindowDays = AppSettingsRules.minimumFootballWindowDays
    static let maximumFootballWindowDays = AppSettingsRules.maximumFootballWindowDays

    let monitor: CalendarMonitor

    @AppStorage(DefaultsKeys.footballTargetCalendarID) var footballTargetCalendarID = ""
    @AppStorage(DefaultsKeys.footballCalendarAlertOption) var footballCalendarAlertOptionRaw = FootballCalendarAlertOption.none.rawValue
    @AppStorage(DefaultsKeys.enableFootballGoalNotifications) var enableFootballGoalNotifications = true
    @AppStorage(DefaultsKeys.includeFootballGoalScorerInNotifications) var includeFootballGoalScorerInNotifications = true
    @AppStorage(DefaultsKeys.enableFootballFinalNotifications) var enableFootballFinalNotifications = true
    @AppStorage(DefaultsKeys.enableFootballAutoAddNotifications) var enableFootballAutoAddNotifications = true
    @AppStorage(DefaultsKeys.showFinishedFootballMatches) var showFinishedFootballMatches = true
    @AppStorage(DefaultsKeys.finishedFootballMatchLookbackDays) var finishedFootballMatchLookbackDays = 7
    @AppStorage(DefaultsKeys.footballMatchLookaheadDays) var footballMatchLookaheadDays = 14
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
    @State var autoAddFootballCompetitionSlugs: Set<String> = []
    @State var competitionSectionsByRegionCache: [(region: FootballCompetitionRegion, sections: [FootballMenuCompetitionSection])] = []
    @State var competitionSectionsWithErrorsCache: [FootballMenuCompetitionSection] = []
    @State var hasAnyCompetitionCardsCache = false
    @State var hasAttemptedCompetitionLoadsCache = false
    @State var liveAndNextDayMatchesByRegionCache: [(region: FootballCompetitionRegion, matches: [FootballFixtureMatch])] = []
    @State var upcomingManagedMatchesCache: [FootballFixtureMatch] = []

    var body: some View {
        GroupBox("Football Fixtures") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add supported football matches to an Apple Calendar managed by Alert Calendar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Suggestions only include matches from the \(FootballCompetitionPreset.suggestionWindowDescription). If a managed fixture falls outside that window, Alert Calendar removes it automatically from Apple Calendar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !hasEventsAccess {
                    emptyState("Grant Calendar access to add football fixtures.")
                } else if writableCalendars.isEmpty {
                    emptyState("No writable event calendars are available.")
                } else {
                    footballContentSection
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            visibleNow = Self.minuteReferenceDate(for: AlertCalendarClock.nowRoundedToSecond())
            finishedFootballMatchLookbackDays = Self.normalizedFootballWindowDays(finishedFootballMatchLookbackDays)
            footballMatchLookaheadDays = Self.normalizedFootballWindowDays(footballMatchLookaheadDays)
            if footballTargetCalendarID.isEmpty,
               let resolvedCalendarID = monitor.footballTargetCalendarID() {
                footballTargetCalendarID = resolvedCalendarID
            }
            monitor.ensureFootballCompetitionSections()
            monitor.refreshManagedFootballTrackingSnapshot(now: visibleNow)
            autoAddFootballCompetitionSlugs = monitor.footballAutoAddCompetitionSlugs()
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
        .onChange(of: footballCalendarAlertOptionRaw) { _ in
            applyFootballCalendarAlertPreference()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let nextSlugs = monitor.footballAutoAddCompetitionSlugs()
            guard autoAddFootballCompetitionSlugs != nextSlugs else { return }
            autoAddFootballCompetitionSlugs = nextSlugs
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
