import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    @ViewBuilder
    var liveFeedsSettingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch selectedFeedsSubsection {
            case .atmosphere:
                atmosphereFeedsSubsection
            case .football:
                footballFeedsSubsection
            case .gameSales:
                gameSalesSubsection
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    var atmosphereFeedsSubsection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                    atmosphereFeedControlsColumn
                        .frame(width: settingsControlColumnWidth, alignment: .topLeading)

                astronomyPreviewSection
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 14) {
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
        VStack(alignment: .leading, spacing: 14) {
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

                        settingsVerticalDivider()

                        astronomyFeedVisibilityCard
                            .frame(minWidth: 360, maxWidth: .infinity, alignment: .topLeading)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        astronomyMasterToggleControl

                        settingsDivider()

                        astronomyFeedVisibilityCard
                    }
                }

                Text("Coordinates are configured from the Permissions tab. Solar moments use those coordinates; lunar phases and orbital highlights are estimated locally.")
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

    func settingsVerticalDivider() -> some View {
        Divider()
            .overlay(Color.primary.opacity(0.04))
            .padding(.vertical, 2)
    }

    var astronomyFeedVisibilityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Visible Feeds")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 170, maximum: 260), alignment: .leading),
                ],
                alignment: .leading,
                spacing: 10
            ) {
                Toggle("Sunrise & Sunset", isOn: $draft.includeSunriseSunset)
                Toggle("Solar Noon & Midnight", isOn: $draft.includeSolarNoonMidnight)
                Toggle("Moon Phases", isOn: $draft.includeMoonPhases)
                Toggle("Orbital Highlights", isOn: $draft.includeOrbitalHighlights)
            }
        }
    }

    @ViewBuilder
    var footballFeedsSubsection: some View {
        SettingsFootballFixturesSectionView(monitor: monitor)
    }

    @ViewBuilder
    var gameSalesSubsection: some View {
        SettingsGameSalesSectionView(monitor: monitor)
    }

    @ViewBuilder
    var calendarSettingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSection(
                title: "Sources",
                subtitle: "Choose the broad item types Alert Calendar is allowed to show before picking individual calendars.",
                systemImage: "calendar.badge.checkmark"
            ) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) {
                        Toggle("Calendar Events", isOn: $draft.includeEvents)
                        Toggle("All-day Events", isOn: $draft.includeAllDayEvents)
                        Toggle("Reminders", isOn: $draft.includeReminders)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Calendar Events", isOn: $draft.includeEvents)
                        Toggle("All-day Events", isOn: $draft.includeAllDayEvents)
                        Toggle("Reminders", isOn: $draft.includeReminders)
                    }
                }
            }

            SettingsCalendarColumnsView(
                includeEvents: draft.includeEvents,
                includeAllDayEvents: draft.includeAllDayEvents,
                includeReminders: draft.includeReminders,
                availableEventCalendars: availableEventCalendars,
                availableReminderCalendars: availableReminderCalendars,
                installedMeetingBrowsers: installedMeetingBrowsers,
                meetingBrowserProfilesByBrowser: meetingBrowserProfilesByBrowser,
                onSelectionChanged: persistCalendarSelectionDraft,
                selectedEventCalendarIDs: $draft.selectedEventCalendarIDs,
                selectedReminderCalendarIDs: $draft.selectedReminderCalendarIDs,
                weekdayOnlyEventCalendarIDs: $draft.weekdayOnlyEventCalendarIDs,
                weekdayOnlyReminderCalendarIDs: $draft.weekdayOnlyReminderCalendarIDs,
                meetingBrowserRouting: $draft.meetingBrowserRouting
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            calendarAuxiliarySettingsContent
        }
    }

    private var hasWeekdayOnlyCalendars: Bool {
        !draft.weekdayOnlyEventCalendarIDs.isEmpty || !draft.weekdayOnlyReminderCalendarIDs.isEmpty
    }

    @ViewBuilder
    private var calendarAuxiliarySettingsContent: some View {
        if hasWeekdayOnlyCalendars {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    nonWorkingDatesSettingsContent
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    meetingBrowserRoutingSettingsContent
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 14) {
                    nonWorkingDatesSettingsContent
                    meetingBrowserRoutingSettingsContent
                }
            }
        } else {
            meetingBrowserRoutingSettingsContent
        }
    }
}
