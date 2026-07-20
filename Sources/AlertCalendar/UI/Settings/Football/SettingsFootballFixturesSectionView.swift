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
            footballIntroSection

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

    private var footballIntroSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: FootballFixtureFormatter.footballLocationSymbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Football Fixtures")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            Text("Add supported football matches to an Apple Calendar managed by Alert Calendar.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Suggestions include matches from the \(FootballCompetitionPreset.suggestionWindowDescription). Managed fixtures outside that window are removed automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }
}
