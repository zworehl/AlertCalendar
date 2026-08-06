import AppKit
import Combine
import SwiftUI

extension SettingsFootballFixturesSectionView {
    var footballContentSection: some View {
        Group {
            if browseMode == .competitions && footballMenuSections.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    footballTopControlsSection

                    emptyState("No competitions are configured right now.")
                }
            } else if browseMode == .competitions {
                footballCompetitionContentSection
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    footballTopControlsSection

                    activeMatchesPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var footballCompetitionContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            footballTopControlsSection

            HStack(alignment: .top, spacing: Self.competitionColumnSpacing) {
                competitionSelectionContentPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                competitionFiltersPanel
                    .frame(width: Self.competitionSidebarWidth, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var footballTopControlsSection: some View {
        footballControlsPanel(showsBrowseControl: true)
    }

    func footballControlsPanel(showsBrowseControl: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            VStack(alignment: .leading, spacing: 12) {
                footballWideControlRow(showsBrowseControl: showsBrowseControl)

                footballCalendarAlertSummary
            }

            VStack(alignment: .leading, spacing: 12) {
                footballPrimaryControlsSection(showsBrowseControl: showsBrowseControl)
                footballCalendarAlertSummary
                footballNotificationControlsSection
            }
        }
        .padding(SettingsVisualMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(panelChrome)
    }

    func footballWideControlRow(showsBrowseControl: Bool) -> some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                addToControlField
                    .frame(width: Self.topMenuControlWidth, alignment: .leading)

                calendarAlertControlField
                    .frame(width: Self.topMenuControlWidth, alignment: .leading)

                SettingsVerticalDivider(height: SettingsVisualMetrics.inlineDividerHeight)

                footballNotificationGroup(layout: .inline)
            }
            .fixedSize(horizontal: true, vertical: false)

            if showsBrowseControl {
                Spacer(minLength: 0)

                showControlField
                    .frame(width: Self.topShowControlWidth, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var footballCalendarAlertSummary: some View {
        Text(footballCalendarAlertSummaryText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    func footballPrimaryControlsSection(showsBrowseControl: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                addToControlField
                    .frame(maxWidth: Self.topMenuControlWidth, alignment: .leading)

                calendarAlertControlField
                    .frame(maxWidth: Self.topMenuControlWidth, alignment: .leading)

                if showsBrowseControl {
                    Spacer(minLength: 0)

                    showControlField
                        .frame(maxWidth: Self.topShowControlWidth, alignment: .trailing)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                addToControlField
                calendarAlertControlField

                if showsBrowseControl {
                    showControlField
                        .frame(maxWidth: Self.topShowControlWidth, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var writableCalendars: [AvailableCalendar] {
        writableEventCalendars
    }

    var footballCalendarAlertOptionBinding: Binding<FootballCalendarAlertOption> {
        $footballCalendarAlertOption
    }

    var footballCalendarAlertSummaryText: String {
        if footballCalendarAlertOption == .none {
            return "Managed football fixtures will be added without an Apple Calendar alert."
        }
        return "All managed football fixtures use the same Apple Calendar alert: \(footballCalendarAlertOption.title.lowercased())."
    }

    var normalizedFinishedMatchLookbackDays: Int {
        Self.normalizedFootballWindowDays(finishedFootballMatchLookbackDays)
    }

    var finishedMatchLookbackDaysBinding: Binding<Double> {
        Binding(
            get: { Double(normalizedFinishedMatchLookbackDays) },
            set: { newValue in
                finishedFootballMatchLookbackDays = Self.normalizedFootballWindowDays(
                    Int(newValue.rounded())
                )
            }
        )
    }

    var normalizedMatchLookaheadDays: Int {
        Self.normalizedFootballWindowDays(footballMatchLookaheadDays)
    }

    var matchLookaheadDaysBinding: Binding<Double> {
        Binding(
            get: { Double(normalizedMatchLookaheadDays) },
            set: { newValue in
                footballMatchLookaheadDays = Self.normalizedFootballWindowDays(
                    Int(newValue.rounded())
                )
            }
        )
    }

    var activeMatchesPanel: some View {
        Group {
            switch browseMode {
            case .competitions:
                competitionListPanel
            case .liveAndNextDay:
                liveAndNextDayPanel
            case .addedMatches:
                addedMatchesPanel
            }
        }
    }

    var upcomingManagedMatches: [FootballFixtureMatch] {
        upcomingManagedMatchesCache
    }

    var upcomingManagedEventCount: Int {
        upcomingManagedMatches.count
    }

    var hasUpcomingAddedMatches: Bool {
        upcomingManagedEventCount > 0
    }

    var isLoadingUpcomingAddedMatches: Bool {
        isRefreshingManagedMatches && !managedFootballMatchIDs.isEmpty && upcomingManagedMatches.isEmpty
    }

    var sharedAddedMatchesCompetitionTitle: String? {
        FootballFixtureFormatter.sharedCompetitionTitle(for: upcomingManagedMatches)
    }

    var sharedAddedMatchesCompetitionLogoURL: URL? {
        guard sharedAddedMatchesCompetitionTitle != nil else { return nil }
        return upcomingManagedMatches.first?.competitionLogoURL
    }

    var sharedAddedMatchesCompetitionLocalLogoPath: String? {
        guard let match = upcomingManagedMatches.first,
              sharedAddedMatchesCompetitionTitle != nil else { return nil }
        return localCompetitionLogoPath(for: match)
    }

    var sharedLiveAndNextDayCompetitionTitle: String? {
        FootballFixtureFormatter.sharedCompetitionTitle(for: displayedLiveAndNextDayMatches)
    }

    var sharedLiveAndNextDayCompetitionLogoURL: URL? {
        guard sharedLiveAndNextDayCompetitionTitle != nil else { return nil }
        return displayedLiveAndNextDayMatches.first?.competitionLogoURL
    }

    var sharedLiveAndNextDayCompetitionLocalLogoPath: String? {
        guard let match = displayedLiveAndNextDayMatches.first,
              sharedLiveAndNextDayCompetitionTitle != nil else { return nil }
        return localCompetitionLogoPath(for: match)
    }

    var competitionSectionsByRegion: [(region: FootballCompetitionRegion, sections: [FootballMenuCompetitionSection])] {
        competitionSectionsByRegionCache
    }

    var selectedCompetitionRegionEntry: (region: FootballCompetitionRegion, sections: [FootballMenuCompetitionSection])? {
        if let selectedCompetitionRegionID,
           let matchingEntry = competitionSectionsByRegion.first(where: { $0.region.id == selectedCompetitionRegionID }) {
            return matchingEntry
        }
        return competitionSectionsByRegion.first
    }

    var selectedCompetitionSections: [FootballMenuCompetitionSection] {
        selectedCompetitionRegionEntry?.sections ?? []
    }

    var selectedCompetitionSection: FootballMenuCompetitionSection? {
        if let selectedCompetitionID,
           let matchingSection = selectedCompetitionSections.first(where: { $0.id == selectedCompetitionID }) {
            return matchingSection
        }
        return selectedCompetitionSections.first
    }

    var liveAndNextDayMatchesByRegion: [(region: FootballCompetitionRegion, matches: [FootballFixtureMatch])] {
        liveAndNextDayMatchesByRegionCache
    }

    var displayedLiveAndNextDayMatches: [FootballFixtureMatch] {
        liveAndNextDayMatchesByRegion.flatMap(\.matches)
    }

    var competitionSectionsWithErrors: [FootballMenuCompetitionSection] {
        competitionSectionsWithErrorsCache
    }

    var hasAnyCompetitionCards: Bool {
        hasAnyCompetitionCardsCache
    }

    var hasAttemptedCompetitionLoads: Bool {
        hasAttemptedCompetitionLoadsCache
    }

    var addToControlField: some View {
        SettingsAddToCalendarPicker(
            selection: $footballTargetCalendarID,
            calendars: writableCalendars,
            pickerTitle: "Add fixtures to calendar",
            helpText: "This calendar is used when you add a football fixture from the list below."
        )
    }

    var showControlField: some View {
        Picker("Football view", selection: $browseMode) {
            ForEach(FootballBrowseMode.allCases) { mode in
                Text(mode.rawValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }

    var calendarAlertControlField: some View {
        SettingsLabeledMenuPicker(
            title: "Calendar Alert",
            pickerTitle: "Football event alert",
            selection: footballCalendarAlertOptionBinding,
            helpText: "Applies the same Apple Calendar alert to every football fixture managed by Alert Calendar, including ones already added."
        ) {
            ForEach(FootballCalendarAlertOption.allCases) { option in
                Text(option.title).tag(option)
            }
        }
    }

    var footballNotificationControlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            footballNotificationGroup(layout: .adaptive)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func footballNotificationGroup(layout: SettingsLabeledCheckboxGroupLayout) -> some View {
        SettingsLabeledCheckboxGroup(
            title: "Notifications",
            helpText: "Applies to football fixtures managed by Alert Calendar.",
            layout: layout
        ) {
            Toggle("Goals", isOn: $enableFootballGoalNotifications)

            Toggle("Disallowed goals", isOn: $enableFootballDisallowedGoalNotifications)

            Toggle("Scorer names", isOn: $includeFootballGoalScorerInNotifications)
                .disabled(!enableFootballGoalNotifications)

            Toggle("Final score", isOn: $enableFootballFinalNotifications)

            Toggle("Added matches", isOn: $enableFootballAutoAddNotifications)
        }
    }
}
