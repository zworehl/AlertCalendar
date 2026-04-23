import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    @ViewBuilder
    var liveFeedsSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Live Feeds") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Manage the non-calendar feeds that can appear in Alert Calendar, including sun moments, lunar phases, orbital highlights, and football fixtures.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            switch selectedFeedsSubsection {
            case .atmosphere:
                atmosphereFeedsSubsection
            case .football:
                footballFeedsSubsection
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    var atmosphereFeedsSubsection: some View {
        GroupBox("Sun, Moon & Orbit") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Toggle("Include atmosphere moments", isOn: $draft.includeAstronomy)
                    InfoTipButton(text: "Adds local sunrise, solar noon, sunset, solar midnight, estimated lunar phase changes, and estimated perihelion, aphelion, solstice, and equinox entries.")
                }

                astronomyFeedVisibilityCard

                Text("The master toggle hides every astronomy feed without clearing the category choices. Configure automatic or manual astronomy coordinates from the Permissions tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

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

    var astronomyFeedVisibilityCard: some View {
        GroupBox("Visible in Feeds") {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 190, maximum: 260), alignment: .leading),
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    Toggle("Sunrise & Sunset", isOn: $draft.includeSunriseSunset)
                    Toggle("Solar Noon & Midnight", isOn: $draft.includeSolarNoonMidnight)
                    Toggle("Moon Phases", isOn: $draft.includeMoonPhases)
                    Toggle("Orbital Highlights", isOn: $draft.includeOrbitalHighlights)
                }

                Text("Solar moments use your configured coordinates. Lunar phases plus orbital highlights are estimated locally and shown in your current time zone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    var footballFeedsSubsection: some View {
        SettingsFootballFixturesSectionView(monitor: monitor)
    }

    @ViewBuilder
    var calendarSettingsContent: some View {
        GroupBox("Sources") {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) {
                        Toggle("Include Calendar Events", isOn: $draft.includeEvents)
                        Toggle("Include All-day Events", isOn: $draft.includeAllDayEvents)
                        Toggle("Include Reminders", isOn: $draft.includeReminders)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Include Calendar Events", isOn: $draft.includeEvents)
                        Toggle("Include All-day Events", isOn: $draft.includeAllDayEvents)
                        Toggle("Include Reminders", isOn: $draft.includeReminders)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        GroupBox("Default Selection") {
            SettingsCalendarColumnsView(
                includeEvents: draft.includeEvents,
                includeAllDayEvents: draft.includeAllDayEvents,
                includeReminders: draft.includeReminders,
                availableEventCalendars: availableEventCalendars,
                availableReminderCalendars: availableReminderCalendars,
                onSelectionChanged: persistCalendarSelectionDraft,
                selectedEventCalendarIDs: $draft.selectedEventCalendarIDs,
                selectedReminderCalendarIDs: $draft.selectedReminderCalendarIDs,
                weekdayOnlyEventCalendarIDs: $draft.weekdayOnlyEventCalendarIDs,
                weekdayOnlyReminderCalendarIDs: $draft.weekdayOnlyReminderCalendarIDs
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
