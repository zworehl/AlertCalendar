import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    @ViewBuilder
    var liveFeedsSettingsContent: some View {
        VStack(alignment: .leading, spacing: SettingsVisualMetrics.pageSpacing) {
            switch selectedFeedsSubsection {
            case .atmosphere:
                atmosphereFeedsSubsection
            case .holidays:
                googleHolidaysSubsection
            case .football:
                footballFeedsSubsection
            case .gameSales:
                gameSalesSubsection
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    var googleHolidaysSubsection: some View {
        SettingsGoogleHolidaysSectionView(
            monitor: monitor,
            selectedCountryIDs: $draft.googleHolidayCountryIDs,
            targetCalendarID: $draft.googleHolidayTargetCalendarID
        )
    }

    @ViewBuilder
    var atmosphereFeedsSubsection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: SettingsVisualMetrics.pageSpacing) {
                    atmosphereFeedControlsColumn
                        .frame(width: settingsControlColumnWidth, alignment: .topLeading)

                astronomyPreviewSection
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: SettingsVisualMetrics.pageSpacing) {
                atmosphereFeedControlsColumn
                astronomyPreviewSection
            }
        }
    }

    var astronomyPreviewSection: some View {
        SettingsAstronomySectionView(
            title: "Astronomy Preview",
            showsCalculatedTimes: true,
            showsSunriseSunset: draft.includeAstronomy && draft.includeSunriseSunset,
            showsSolarNoonMidnight: draft.includeAstronomy && draft.includeSolarNoonMidnight,
            showsMoonPhases: draft.includeAstronomy && draft.includeMoonPhases,
            showsOrbitalHighlights: draft.includeAstronomy && draft.includeOrbitalHighlights,
            astronomyLatitude: draft.astronomyLatitude,
            astronomyLongitude: draft.astronomyLongitude,
            solarTimesProvider: { day, coordinate, timeZone in
                monitor.solarTimes(for: day, coordinate: coordinate, timeZone: timeZone)
            },
            nextLunarPhasesProvider: { date in
                monitor.nextLunarPhaseMoments(from: date)
            },
            nextOrbitalHighlightsProvider: { date in
                monitor.nextOrbitalHighlights(from: date)
            }
        )
    }

    var atmosphereFeedControlsColumn: some View {
        VStack(alignment: .leading, spacing: SettingsVisualMetrics.pageSpacing) {
            astronomyFeedControlsSection
        }
    }

    var astronomyFeedControlsSection: some View {
        settingsSection(
            title: "Sun, Moon & Orbit",
            subtitle: "Manage the non-calendar moments that can appear alongside your schedule.",
            systemImage: "sun.max"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        astronomyMasterToggleControl
                            .frame(minWidth: 280, maxWidth: .infinity, alignment: .topLeading)

                        SettingsVerticalDivider()

                        astronomyFeedVisibilityCard
                            .frame(minWidth: 360, maxWidth: .infinity, alignment: .topLeading)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        astronomyMasterToggleControl

                        settingsDivider()

                        astronomyFeedVisibilityCard
                    }
                }

                Text("Coordinates are configured from the Access tab. Solar moments use those coordinates; lunar phases and orbital highlights are estimated locally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var astronomyMasterToggleControl: some View {
        settingsControlRow(
            title: "Atmosphere moments",
            detail: "Hides or shows all astronomy feeds without clearing individual choices."
        ) {
            Toggle("Include atmosphere moments", isOn: $draft.includeAstronomy)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(Text("Include atmosphere moments"))
        }
    }

    var astronomyFeedVisibilityCard: some View {
        SettingsLabeledCheckboxGroup(
            title: "Visible Feeds",
            minimumItemWidth: 170,
            maximumItemWidth: 260
        ) {
            Toggle("Sunrise & Sunset", isOn: $draft.includeSunriseSunset)
            Toggle("Solar Noon & Midnight", isOn: $draft.includeSolarNoonMidnight)
            Toggle("Moon Phases", isOn: $draft.includeMoonPhases)
            Toggle("Orbital Highlights", isOn: $draft.includeOrbitalHighlights)
        }
    }

    @ViewBuilder
    var footballFeedsSubsection: some View {
        SettingsFootballFixturesSectionView(
            monitor: monitor,
            footballTargetCalendarID: $draft.footballTargetCalendarID,
            autoAddFootballCompetitionSlugs: $draft.footballAutoAddCompetitionSlugs,
            footballCalendarAlertOption: $draft.footballCalendarAlertOption,
            enableFootballGoalNotifications: $draft.enableFootballGoalNotifications,
            enableFootballDisallowedGoalNotifications: $draft.enableFootballDisallowedGoalNotifications,
            includeFootballGoalScorerInNotifications: $draft.includeFootballGoalScorerInNotifications,
            enableFootballFinalNotifications: $draft.enableFootballFinalNotifications,
            enableFootballAutoAddNotifications: $draft.enableFootballAutoAddNotifications,
            showFinishedFootballMatches: $draft.showFinishedFootballMatches,
            finishedFootballMatchLookbackDays: $draft.finishedFootballMatchLookbackDays,
            footballMatchLookaheadDays: $draft.footballMatchLookaheadDays
        )
    }

    @ViewBuilder
    var gameSalesSubsection: some View {
        SettingsGameSalesSectionView(
            monitor: monitor,
            targetCalendarID: $draft.gameSaleTargetCalendarID,
            calendarAlertOption: $draft.gameSaleCalendarAlertOption,
            enableAutoAddNotifications: $draft.enableGameSaleAutoAddNotifications,
            autoAddStores: $draft.gameSaleAutoAddStores
        )
    }

    @ViewBuilder
    var calendarSettingsContent: some View {
        VStack(alignment: .leading, spacing: SettingsVisualMetrics.pageSpacing) {
            calendarSourceSelectionPanel

            meetingBrowserProfileIssuesBanner

            SettingsCalendarColumnsView(
                includeEvents: draft.includeEvents,
                includeAllDayEvents: draft.includeAllDayEvents,
                includeReminders: draft.includeReminders,
                availableEventCalendars: availableEventCalendars,
                availableReminderCalendars: availableReminderCalendars,
                installedMeetingBrowsers: installedMeetingBrowsers,
                meetingBrowserProfilesByBrowser: meetingBrowserProfilesByBrowser,
                meetingBrowserProfileIssuesByBrowser: meetingBrowserProfileIssuesByBrowser,
                onSelectionChanged: {},
                selectedEventCalendarIDs: $draft.selectedEventCalendarIDs,
                selectedReminderCalendarIDs: $draft.selectedReminderCalendarIDs,
                weekdayOnlyEventCalendarIDs: $draft.weekdayOnlyEventCalendarIDs,
                weekdayOnlyReminderCalendarIDs: $draft.weekdayOnlyReminderCalendarIDs,
                calendarAlertRules: $draft.calendarAlertRules,
                meetingBrowserRouting: $draft.meetingBrowserRouting
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            calendarAuxiliarySettingsContent
        }
    }

    var calendarSourceSelectionPanel: some View {
        SettingsLabeledCheckboxGroup(
            title: "Sources",
            helpText: "Choose the broad item types Alert Calendar can show before selecting individual calendars."
        ) {
            Toggle("Calendar Events", isOn: $draft.includeEvents)
            Toggle("All-day Events", isOn: $draft.includeAllDayEvents)
            Toggle("Reminders", isOn: $draft.includeReminders)
        }
        .padding(SettingsVisualMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(SettingsPanelChrome())
    }

    private var hasWeekdayOnlyCalendars: Bool {
        !draft.weekdayOnlyEventCalendarIDs.isEmpty || !draft.weekdayOnlyReminderCalendarIDs.isEmpty
    }

    @ViewBuilder
    private var calendarAuxiliarySettingsContent: some View {
        if hasWeekdayOnlyCalendars {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: SettingsVisualMetrics.pageSpacing) {
                    nonWorkingDatesSettingsContent
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    meetingBrowserRoutingSettingsContent
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: SettingsVisualMetrics.pageSpacing) {
                    nonWorkingDatesSettingsContent
                    meetingBrowserRoutingSettingsContent
                }
            }
        } else {
            meetingBrowserRoutingSettingsContent
        }
    }
}
