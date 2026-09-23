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
        .frame(
            maxWidth: .infinity,
            maxHeight: selectedFeedsSubsection.usesEmbeddedDetailScroller ? .infinity : nil,
            alignment: .topLeading
        )
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
        VStack(alignment: .leading, spacing: SettingsVisualMetrics.pageSpacing) {
            astronomyFeedControlsSection

            SettingsSectionDivider()

            astronomyPreviewSection
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var astronomyCoordinateStatus: String? {
        guard astronomyLocationStatus != "Manual coordinates" else { return nil }
        if astronomyLocationStatus.hasPrefix("Auto location:")
            || astronomyLocationStatus.hasPrefix("Approximate auto location:")
            || astronomyLocationStatus.hasPrefix("Detected location:")
            || astronomyLocationStatus.hasPrefix("Detected approximate location:")
            || astronomyLocationStatus.contains("Using saved coordinates:") {
            return nil
        }
        return astronomyLocationStatus
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
            availableWidth: max(settingsWindowWidth - (SettingsVisualMetrics.detailHorizontalPadding * 2), 0),
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

    var astronomyFeedControlsSection: some View {
        let contentWidth = max(settingsWindowWidth - SettingsVisualMetrics.detailHorizontalPadding * 2, 0)
        // Each column needs room for its controls, including a two-column feed list.
        // AnyLayout retains coordinate editing state when the window changes size.
        let layout = contentWidth >= 1_120
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))

        return layout {
            astronomyMasterToggleControl
                .frame(maxWidth: .infinity, alignment: .topLeading)

            astronomyFeedVisibilitySection
                .frame(maxWidth: .infinity, alignment: .topLeading)

            AstronomyCoordinatesCard(
                useAutomaticAstronomyLocation: $draft.useAutomaticAstronomyLocation,
                astronomyLatitude: $draft.astronomyLatitude,
                astronomyLongitude: $draft.astronomyLongitude,
                locationStatus: astronomyCoordinateStatus,
                onDetectNow: detectLocation
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

    var astronomyFeedVisibilitySection: some View {
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
            finishedFootballMatchLookbackDays: $draft.finishedFootballMatchLookbackDays,
            footballMatchLookaheadDays: $draft.footballMatchLookaheadDays,
            pendingCalendarChanges: $pendingChanges.footballFixtures
        )
    }

    @ViewBuilder
    var gameSalesSubsection: some View {
        SettingsGameSalesSectionView(
            monitor: monitor,
            targetCalendarID: $draft.gameSaleTargetCalendarID,
            calendarAlertOption: $draft.gameSaleCalendarAlertOption,
            enableAutoAddNotifications: $draft.enableGameSaleAutoAddNotifications,
            autoAddStores: $draft.gameSaleAutoAddStores,
            pendingCalendarChanges: $pendingChanges.gameSales
        )
    }

    @ViewBuilder
    var calendarSettingsContent: some View {
        VStack(alignment: .leading, spacing: SettingsVisualMetrics.pageSpacing) {
            if settingsWindowWidth >= 960 {
                HStack(alignment: .top, spacing: SettingsVisualMetrics.pageSpacing) {
                    VStack(alignment: .leading, spacing: SettingsVisualMetrics.pageSpacing) {
                        calendarRoutingColumn
                        focusFiltersSection
                        calendarColumnsView(mode: .remindersOnly)
                    }
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    calendarColumnsView(mode: .eventsOnly)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                VStack(alignment: .leading, spacing: SettingsVisualMetrics.pageSpacing) {
                    calendarRoutingColumn
                    focusFiltersSection
                    calendarColumnsView(mode: .remindersOnly)
                    calendarColumnsView(mode: .eventsOnly)
                }
            }
        }
    }

    func calendarColumnsView(mode: SettingsCalendarColumnsView.Mode) -> some View {
        SettingsCalendarColumnsView(
            mode: mode,
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
            calendarAlertRules: $draft.calendarAlertRules,
            meetingBrowserRouting: $draft.meetingBrowserRouting
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    var calendarRoutingColumn: some View {
        VStack(alignment: .leading, spacing: SettingsVisualMetrics.pageSpacing) {
            calendarSourceSelectionPanel
            meetingBrowserRoutingSettingsContent
            meetingBrowserProfileIssuesBanner
        }
    }

    var focusFiltersSection: some View {
        SettingsFocusFiltersSectionView(
            monitor: monitor,
            eventCalendars: availableEventCalendars,
            reminderCalendars: availableReminderCalendars
        )
    }

    var calendarSourceSelectionPanel: some View {
        SettingsLabeledCheckboxGroup(
            title: "Visible Content",
            helpText: "Choose the broad item types Alert Calendar can show before selecting individual calendars."
        ) {
            Toggle("Calendar Events", isOn: $draft.includeEvents)
            Toggle("All-day Events", isOn: $draft.includeAllDayEvents)
            Toggle("Reminders", isOn: $draft.includeReminders)
        }
        .settingsPanelSurface()
    }

}
