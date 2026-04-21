import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    @ViewBuilder
    var activeSettingsContent: some View {
        switch selectedTab {
        case .general:
            generalSettingsContent
        case .feeds:
            liveFeedsSettingsContent
        case .calendars:
            calendarSettingsContent
        case .permissions:
            permissionsSettingsContent
        }
    }

    @ViewBuilder
    var generalSettingsContent: some View {
        let maxContextualPreviewLeadMinutes = maximumContextualPreviewLeadMinutes(
            dropdownWindowHours: draft.lookAheadHours
        )

        GroupBox("Alert") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable red blinking alert", isOn: $draft.enableBlinkAlert)
                stepperRow(
                    title: "Alert lead time",
                    valueText: Self.durationValueText(
                        value: draft.alertLeadMinutes,
                        singular: "minute",
                        plural: "minutes"
                    ),
                    helpText: "How many minutes before the event start the alert state begins."
                ) {
                    Stepper("", value: $draft.alertLeadMinutes, in: 1 ... 60)
                        .labelsHidden()
                }

                stepperRow(
                    title: "Queue rotation",
                    valueText: Self.durationValueText(
                        value: draft.concurrentEventRotationSeconds,
                        singular: "second",
                        plural: "seconds"
                    ),
                    helpText: "Rotation interval for all items in the menu bar queue, including all-day events."
                ) {
                    Stepper("", value: $draft.concurrentEventRotationSeconds, in: 5 ... 300, step: 5)
                        .labelsHidden()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        GroupBox("Display") {
            VStack(alignment: .leading, spacing: 10) {
                stepperRow(
                    title: "Menu bar rotation window",
                    valueText: Self.menuBarRotationWindowValueText(
                        minutes: draft.menuBarRotationWindowMinutes
                    ),
                    helpText: "Timed events and reminders rotate in the menu bar only if they are active, overdue, or inside this window. This window must stay smaller than the dropdown time window."
                ) {
                    Stepper {
                        EmptyView()
                    } onIncrement: {
                        draft.menuBarRotationWindowMinutes = Self.adjustedMenuBarRotationWindowMinutes(
                            currentValue: draft.menuBarRotationWindowMinutes,
                            incrementing: true,
                            dropdownWindowHours: draft.lookAheadHours
                        )
                    } onDecrement: {
                        draft.menuBarRotationWindowMinutes = Self.adjustedMenuBarRotationWindowMinutes(
                            currentValue: draft.menuBarRotationWindowMinutes,
                            incrementing: false,
                            dropdownWindowHours: draft.lookAheadHours
                        )
                    }
                        .labelsHidden()
                }

                stepperRow(
                    title: "Dropdown time window",
                    valueText: Self.durationValueText(
                        value: draft.lookAheadHours,
                        singular: "hour",
                        plural: "hours"
                    ),
                    helpText: "Upcoming timed items only appear in the dropdown if they fall inside this window. It must stay larger than the menu bar rotation window."
                ) {
                    Stepper("", value: $draft.lookAheadHours, in: 1 ... 168)
                        .labelsHidden()
                }

                stepperRow(
                    title: "Contextual preview lead time",
                    valueText: Self.menuBarRotationWindowValueText(
                        minutes: draft.contextualPreviewLeadMinutes
                    ),
                    helpText: "Contextual previews only appear for active events or ones starting inside this window. Applies to maps, invitees, daylight events, and football fixtures."
                ) {
                    Stepper("", value: $draft.contextualPreviewLeadMinutes, in: 60 ... maxContextualPreviewLeadMinutes, step: 60)
                        .labelsHidden()
                }

                stepperRow(
                    title: "Items in dropdown list",
                    valueText: "\(draft.maxListItems)"
                ) {
                    Stepper("", value: $draft.maxListItems, in: 3 ... 20)
                        .labelsHidden()
                }

                stepperRow(
                    title: "Menu bar font size",
                    valueText: String(format: "%.1f pt", draft.menuBarFontSize)
                ) {
                    Stepper("", value: $draft.menuBarFontSize, in: 10 ... 18, step: 0.5)
                        .labelsHidden()
                }

                HStack(spacing: 6) {
                    Toggle("Use ellipsis for long titles", isOn: $draft.useEventTitleEllipsis)
                    InfoTipButton(text: "If enabled, long menu bar titles are truncated with an ellipsis.")
                }

                if draft.useEventTitleEllipsis {
                    stepperRow(
                        title: "Title max characters",
                        valueText: "\(draft.eventTitleMaxCharacters)"
                    ) {
                        Stepper("", value: $draft.eventTitleMaxCharacters, in: 8 ... 80)
                            .labelsHidden()
                    }
                }

                HStack(spacing: 6) {
                    Toggle("Simplified countdown (largest unit only)", isOn: $draft.useSimplifiedCountdown)
                    InfoTipButton(text: "Displays only the biggest time unit. Example: \"in 2h\" instead of \"in 2h 37m\".")
                }

                HStack {
                    HStack(spacing: 6) {
                        Text("Active event timer")
                        InfoTipButton(text: "Choose whether active events show elapsed time since start or time remaining until end.")
                    }
                    Spacer()
                    Picker("Active event timer", selection: $draft.activeEventDisplayMode) {
                        ForEach(ActiveEventDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

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

    @ViewBuilder
    var permissionsSettingsContent: some View {
        GroupBox("Permissions Overview") {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) {
                        statusPill(title: "Current Access", value: calendarAccessDescription)
                        statusPill(
                            title: "Last Refresh",
                            value: lastRefreshDate.map { Self.settingsDateFormatter.string(from: $0) } ?? "Waiting for first sync..."
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        statusPill(title: "Current Access", value: calendarAccessDescription)
                        statusPill(
                            title: "Last Refresh",
                            value: lastRefreshDate.map { Self.settingsDateFormatter.string(from: $0) } ?? "Waiting for first sync..."
                        )
                    }
                }

                Text("Each permission can be retried individually. If macOS already denied one, use the matching Settings shortcut to allow it again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        GroupBox("Permission Actions") {
            HStack(alignment: .top, spacing: 12) {
                ForEach(SettingsPermissionKind.allCases) { permission in
                    permissionActionCard(for: permission)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        GroupBox("Astronomy Location") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose whether astronomy previews should use automatic system location or manual coordinates. If you do not want to grant Location access, switch automatic location off and enter your own latitude/longitude below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                AstronomyCoordinatesCard(
                    useAutomaticAstronomyLocation: $draft.useAutomaticAstronomyLocation,
                    astronomyLatitude: $draft.astronomyLatitude,
                    astronomyLongitude: $draft.astronomyLongitude,
                    astronomyLocationStatus: astronomyLocationStatus,
                    onDetectNow: detectLocation
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        GroupBox("Global Shortcuts") {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Button {
                            refreshPermissionStatuses()
                        } label: {
                            Label("Refresh Permission Status", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            openPrivacySettings()
                        } label: {
                            Label("Open Privacy Settings", systemImage: "gearshape")
                        }
                        .buttonStyle(.bordered)
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            refreshPermissionStatuses()
                        } label: {
                            Label("Refresh Permission Status", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            openPrivacySettings()
                        } label: {
                            Label("Open Privacy Settings", systemImage: "gearshape")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Text("macOS only re-shows native permission prompts when the system considers the app eligible. If a permission stays denied, the per-permission Settings button is the reliable path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}
