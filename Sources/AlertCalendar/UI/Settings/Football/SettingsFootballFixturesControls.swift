import AppKit
import Combine
import SwiftUI

extension SettingsFootballFixturesSectionView {
    var footballContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            footballTopControlsSection

            if browseMode == .competitions && footballMenuSections.isEmpty {
                emptyState("No competitions are configured right now.")
            } else {
                activeMatchesPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var writableCalendars: [AvailableCalendar] {
        writableEventCalendars
    }

    var footballCalendarAlertOption: FootballCalendarAlertOption {
        FootballCalendarAlertOption(rawValue: footballCalendarAlertOptionRaw) ?? .none
    }

    var footballCalendarAlertOptionBinding: Binding<FootballCalendarAlertOption> {
        Binding(
            get: { footballCalendarAlertOption },
            set: { footballCalendarAlertOptionRaw = $0.rawValue }
        )
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

    var footballTopControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            footballPrimaryControlsSection
            footballNotificationControlsSection
        }
    }

    var footballPrimaryControlsSection: some View {
        HStack(alignment: .top, spacing: 16) {
            addToControlField
                .frame(maxWidth: Self.topMenuControlWidth, alignment: .leading)

            Spacer(minLength: 0)

            showControlField
                .frame(maxWidth: Self.topShowControlWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var addToControlField: some View {
        footballControlField(
            title: "Add To",
            helpText: "This calendar is used when you add a football fixture from the list below.",
            isInline: true
        ) {
            Picker("Add fixtures to calendar", selection: $footballTargetCalendarID) {
                ForEach(writableCalendars) { calendar in
                    Text(calendar.title).tag(calendar.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    var showControlField: some View {
        Picker("Football view", selection: $browseMode) {
            ForEach(FootballBrowseMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    var calendarAlertControlField: some View {
        footballControlField(
            title: "Calendar Alert",
            helpText: "Applies the same Apple Calendar alert to every football fixture managed by Alert Calendar, including ones already added.",
            isInline: true
        ) {
            Picker("Football event alert", selection: footballCalendarAlertOptionBinding) {
                ForEach(FootballCalendarAlertOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    var footballNotificationControlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            footballControlTitle(
                title: "Notifications",
                helpText: "Applies to football fixtures managed by Alert Calendar."
            )

            HStack(alignment: .center, spacing: 18) {
                Toggle("Goals", isOn: $enableFootballGoalNotifications)
                    .toggleStyle(.checkbox)

                Toggle("Scorer names", isOn: $includeFootballGoalScorerInNotifications)
                    .toggleStyle(.checkbox)
                    .disabled(!enableFootballGoalNotifications)

                Toggle("Final score", isOn: $enableFootballFinalNotifications)
                    .toggleStyle(.checkbox)

                Toggle("Added matches", isOn: $enableFootballAutoAddNotifications)
                    .toggleStyle(.checkbox)
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func footballControlField<Control: View>(
        title: String,
        helpText: String? = nil,
        isInline: Bool = false,
        @ViewBuilder control: () -> Control
    ) -> some View {
        Group {
            if isInline {
                HStack(alignment: .center, spacing: 10) {
                    footballControlTitle(title: title, helpText: helpText)
                        .frame(width: Self.inlineFieldLabelWidth, alignment: .leading)

                    control()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    footballControlTitle(title: title, helpText: helpText)
                    control()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func footballControlTitle(title: String, helpText: String?) -> some View {
        HStack(spacing: 6) {
            Text(title)
            if let helpText {
                InfoTipButton(text: helpText)
            }
        }
        .font(.subheadline.weight(.medium))
    }


}
