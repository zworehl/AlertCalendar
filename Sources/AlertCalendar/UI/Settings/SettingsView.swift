import AppKit
import SwiftUI

struct SettingsView: View {
    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case calendars = "Calendars & Reminders"
        case permissions = "Permissions"

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .general:
                return "slider.horizontal.3"
            case .calendars:
                return "calendar"
            case .permissions:
                return "lock.shield"
            }
        }
    }

    let monitor: CalendarMonitor

    @AppStorage(DefaultsKeys.includeEvents) private var includeEvents = true
    @AppStorage(DefaultsKeys.includeAllDayEvents) private var includeAllDayEvents = true
    @AppStorage(DefaultsKeys.includeReminders) private var includeReminders = true
    @AppStorage(DefaultsKeys.includeWeather) private var includeWeather = true
    @AppStorage(DefaultsKeys.lookAheadHours) private var lookAheadHours = 24
    @AppStorage(DefaultsKeys.alertLeadMinutes) private var alertLeadMinutes = 5
    @AppStorage(DefaultsKeys.nearUpcomingAlternateMinutes) private var nearUpcomingAlternateMinutes = 10
    @AppStorage(DefaultsKeys.concurrentEventRotationSeconds) private var concurrentEventRotationSeconds = 30
    @AppStorage(DefaultsKeys.maxListItems) private var maxListItems = 8
    @AppStorage(DefaultsKeys.enableBlinkAlert) private var enableBlinkAlert = true
    @AppStorage(DefaultsKeys.menuBarFontSize) private var menuBarFontSize = 13.0
    @AppStorage(DefaultsKeys.useSimplifiedCountdown) private var useSimplifiedCountdown = true
    @AppStorage(DefaultsKeys.activeEventDisplayMode) private var activeEventDisplayModeRaw = ActiveEventDisplayMode.remaining.rawValue
    @AppStorage(DefaultsKeys.useEventTitleEllipsis) private var useEventTitleEllipsis = true
    @AppStorage(DefaultsKeys.eventTitleMaxCharacters) private var eventTitleMaxCharacters = 22
    @AppStorage(DefaultsKeys.includeAstronomy) private var includeAstronomy = true
    @AppStorage(DefaultsKeys.useAutomaticAstronomyLocation) private var useAutomaticAstronomyLocation = false
    @AppStorage(DefaultsKeys.astronomyColorID) private var astronomyColorID = "blue"
    @AppStorage(DefaultsKeys.astronomyLatitude) private var astronomyLatitude = 18.4655
    @AppStorage(DefaultsKeys.astronomyLongitude) private var astronomyLongitude = -66.1057

    @State private var draft = SettingsDraft.empty
    @State private var didLoad = false
    @State private var selectedTab: SettingsTab = .general
    @State private var isRequestingPermissions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsHeader

            Picker("Settings section", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.symbolName)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 2)

            if selectedTab == .general {
                generalSettingsContent
            } else if selectedTab == .calendars {
                calendarSettingsContent
            } else {
                permissionsSettingsContent
            }

            if selectedTab == .permissions {
                HStack {
                    Spacer()
                    Button("Refresh now") {
                        monitor.refreshNow()
                    }
                }
            } else {
                HStack {
                    Button("Cancel") {
                        resetDraft()
                    }
                    .disabled(!hasUnsavedChanges)

                    Button("Apply") {
                        applyDraft()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasUnsavedChanges)

                    Spacer()

                    Button("Refresh now") {
                        monitor.refreshNow()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 620, idealWidth: 700)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            if !didLoad {
                monitor.refreshAvailableCalendars()
                resetDraft()
                didLoad = true
            }
        }
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Preferences")
                .font(.title2.weight(.semibold))
            Text("Alert Calendar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var generalSettingsContent: some View {
        GroupBox("Alert") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable red blinking alert", isOn: $draft.enableBlinkAlert)
                stepperRow(
                    title: "Alert lead time",
                    valueText: "\(draft.alertLeadMinutes) minutes",
                    helpText: "How many minutes before the event start the alert state begins."
                ) {
                    Stepper("", value: $draft.alertLeadMinutes, in: 1 ... 60)
                        .labelsHidden()
                }

                stepperRow(
                    title: "Alternate near upcoming event",
                    valueText: "\(draft.nearUpcomingAlternateMinutes) minutes",
                    helpText: "If an event is in progress and another starts within this window, the event slot alternates between them."
                ) {
                    Stepper("", value: $draft.nearUpcomingAlternateMinutes, in: 5 ... 120, step: 5)
                        .labelsHidden()
                }

                stepperRow(
                    title: "Queue rotation",
                    valueText: "\(draft.concurrentEventRotationSeconds) seconds",
                    helpText: "Rotation interval for all items in the menu bar queue, including all-day events."
                ) {
                    Stepper("", value: $draft.concurrentEventRotationSeconds, in: 5 ... 300, step: 5)
                        .labelsHidden()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        GroupBox("Astronomy & Weather") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Toggle("Include sun moments (sunrise/noon/sunset/midnight)", isOn: $draft.includeAstronomy)
                    InfoTipButton(text: "Adds local sunrise, solar noon, sunset, and solar midnight entries calculated from your configured coordinates.")
                }

                HStack(spacing: 6) {
                    Toggle("Include rain forecast (Open-Meteo)", isOn: $draft.includeWeather)
                    InfoTipButton(text: "Shows upcoming rain estimate in the menu bar. Uses the same coordinates configured below.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if draft.includeAstronomy || draft.includeWeather {
            SettingsAstronomySectionView(
                useAutomaticAstronomyLocation: $draft.useAutomaticAstronomyLocation,
                astronomyLatitude: $draft.astronomyLatitude,
                astronomyLongitude: $draft.astronomyLongitude,
                astronomyLocationStatus: monitor.astronomyLocationStatus,
                onDetectNow: detectLocation,
                solarTimesProvider: { day, coordinate, timeZone in
                    monitor.solarTimes(for: day, coordinate: coordinate, timeZone: timeZone)
                }
            )
        }

        GroupBox("Display") {
            VStack(alignment: .leading, spacing: 10) {
                stepperRow(
                    title: "Look-ahead window",
                    valueText: "\(draft.lookAheadHours) hours"
                ) {
                    Stepper("", value: $draft.lookAheadHours, in: 1 ... 168)
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
    private var calendarSettingsContent: some View {
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
                availableEventCalendars: monitor.availableEventCalendars,
                availableReminderCalendars: monitor.availableReminderCalendars,
                selectedEventCalendarIDs: $draft.selectedEventCalendarIDs,
                selectedReminderCalendarIDs: $draft.selectedReminderCalendarIDs,
                weekdayOnlyEventCalendarIDs: $draft.weekdayOnlyEventCalendarIDs,
                weekdayOnlyReminderCalendarIDs: $draft.weekdayOnlyReminderCalendarIDs
            )
        }
    }

    @ViewBuilder
    private var permissionsSettingsContent: some View {
        GroupBox("Access Status") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    statusPill(title: "Calendar Access", value: monitor.calendarAccessDescription)
                    statusPill(
                        title: "Last Refresh",
                        value: monitor.lastRefreshDate.map { Self.settingsDateFormatter.string(from: $0) } ?? "Waiting for first sync..."
                    )
                }
                VStack(alignment: .leading, spacing: 8) {
                    statusPill(title: "Calendar Access", value: monitor.calendarAccessDescription)
                    statusPill(
                        title: "Last Refresh",
                        value: monitor.lastRefreshDate.map { Self.settingsDateFormatter.string(from: $0) } ?? "Waiting for first sync..."
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        GroupBox("Permission Actions") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        requestPermissionsAgain()
                    } label: {
                        Label(
                            isRequestingPermissions ? "Requesting access..." : "Request Permissions Again",
                            systemImage: isRequestingPermissions ? "hourglass" : "lock.open"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRequestingPermissions)

                    Button {
                        openPrivacySettings()
                    } label: {
                        Label("Open Privacy Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                }

                Text("If permissions were previously denied, enable Calendar and Reminders access in macOS Privacy settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hasUnsavedChanges: Bool {
        didLoad && draft != storedDraft()
    }

    private func storedDraft() -> SettingsDraft {
        SettingsDraft(
            includeEvents: includeEvents,
            includeAllDayEvents: includeAllDayEvents,
            includeReminders: includeReminders,
            includeWeather: includeWeather,
            lookAheadHours: lookAheadHours,
            alertLeadMinutes: alertLeadMinutes,
            nearUpcomingAlternateMinutes: normalizedNearUpcomingAlternateMinutes(nearUpcomingAlternateMinutes),
            concurrentEventRotationSeconds: concurrentEventRotationSeconds,
            maxListItems: maxListItems,
            enableBlinkAlert: enableBlinkAlert,
            menuBarFontSize: menuBarFontSize,
            useSimplifiedCountdown: useSimplifiedCountdown,
            activeEventDisplayMode: ActiveEventDisplayMode(rawValue: activeEventDisplayModeRaw) ?? .remaining,
            useEventTitleEllipsis: useEventTitleEllipsis,
            eventTitleMaxCharacters: eventTitleMaxCharacters,
            includeAstronomy: includeAstronomy,
            useAutomaticAstronomyLocation: useAutomaticAstronomyLocation,
            astronomyColorID: astronomyColorID,
            astronomyLatitude: astronomyLatitude,
            astronomyLongitude: astronomyLongitude,
            selectedEventCalendarIDs: monitor.selectedCalendarIDs(for: .event),
            selectedReminderCalendarIDs: monitor.selectedCalendarIDs(for: .reminder),
            weekdayOnlyEventCalendarIDs: monitor.weekdayOnlyCalendarIDs(for: .event),
            weekdayOnlyReminderCalendarIDs: monitor.weekdayOnlyCalendarIDs(for: .reminder)
        )
    }

    private func resetDraft() {
        draft = storedDraft()
    }

    private func applyDraft() {
        let oldAutoLocation = useAutomaticAstronomyLocation

        includeEvents = draft.includeEvents
        includeAllDayEvents = draft.includeAllDayEvents
        includeReminders = draft.includeReminders
        includeWeather = draft.includeWeather
        lookAheadHours = draft.lookAheadHours
        alertLeadMinutes = draft.alertLeadMinutes
        nearUpcomingAlternateMinutes = normalizedNearUpcomingAlternateMinutes(draft.nearUpcomingAlternateMinutes)
        concurrentEventRotationSeconds = draft.concurrentEventRotationSeconds
        maxListItems = draft.maxListItems
        enableBlinkAlert = draft.enableBlinkAlert
        menuBarFontSize = draft.menuBarFontSize
        useSimplifiedCountdown = draft.useSimplifiedCountdown
        activeEventDisplayModeRaw = draft.activeEventDisplayMode.rawValue
        useEventTitleEllipsis = draft.useEventTitleEllipsis
        eventTitleMaxCharacters = draft.eventTitleMaxCharacters
        includeAstronomy = draft.includeAstronomy
        useAutomaticAstronomyLocation = draft.useAutomaticAstronomyLocation
        astronomyColorID = draft.astronomyColorID
        astronomyLatitude = roundTo3Decimals(draft.astronomyLatitude)
        astronomyLongitude = roundTo3Decimals(draft.astronomyLongitude)

        monitor.defaults.set(Array(draft.selectedEventCalendarIDs), forKey: DefaultsKeys.selectedEventCalendarIDs)
        monitor.defaults.set(Array(draft.selectedReminderCalendarIDs), forKey: DefaultsKeys.selectedReminderCalendarIDs)
        monitor.defaults.set(Array(draft.weekdayOnlyEventCalendarIDs), forKey: DefaultsKeys.weekdayOnlyEventCalendarIDs)
        monitor.defaults.set(Array(draft.weekdayOnlyReminderCalendarIDs), forKey: DefaultsKeys.weekdayOnlyReminderCalendarIDs)

        if draft.useAutomaticAstronomyLocation, !oldAutoLocation {
            monitor.refreshAstronomyCoordinatesFromSystem()
        } else if !draft.useAutomaticAstronomyLocation {
            monitor.astronomyLocationStatus = "Manual coordinates"
            monitor.refreshNow()
        } else {
            monitor.refreshNow()
        }
    }

    private func detectLocation() {
        Task { @MainActor in
            guard let coordinate = await monitor.detectAstronomyCoordinate() else { return }
            draft.astronomyLatitude = roundTo3Decimals(coordinate.latitude)
            draft.astronomyLongitude = roundTo3Decimals(coordinate.longitude)
        }
    }

    private func roundTo3Decimals(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    private func normalizedNearUpcomingAlternateMinutes(_ value: Int) -> Int {
        let clamped = max(5, min(120, value))
        return Int((Double(clamped) / 5.0).rounded()) * 5
    }

    private func requestPermissionsAgain() {
        guard !isRequestingPermissions else { return }
        isRequestingPermissions = true

        Task { @MainActor in
            await monitor.requestCalendarAccess()
            monitor.refreshAvailableCalendars()
            monitor.refreshNow()
            isRequestingPermissions = false
        }
    }

    private func openPrivacySettings() {
        if let calendarURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(calendarURL)
        }
    }

    private func statusPill(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(title):")
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func stepperRow<Control: View>(title: String, valueText: String, helpText: String? = nil, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            HStack(spacing: 6) {
                Text(title)
                if let helpText {
                    InfoTipButton(text: helpText)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                control()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 170, alignment: .trailing)
        }
    }

    private static let settingsDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy h:mm:ss a"
        return formatter
    }()
}

private struct SettingsDraft: Equatable {
    var includeEvents: Bool
    var includeAllDayEvents: Bool
    var includeReminders: Bool
    var includeWeather: Bool
    var lookAheadHours: Int
    var alertLeadMinutes: Int
    var nearUpcomingAlternateMinutes: Int
    var concurrentEventRotationSeconds: Int
    var maxListItems: Int
    var enableBlinkAlert: Bool
    var menuBarFontSize: Double
    var useSimplifiedCountdown: Bool
    var activeEventDisplayMode: ActiveEventDisplayMode
    var useEventTitleEllipsis: Bool
    var eventTitleMaxCharacters: Int
    var includeAstronomy: Bool
    var useAutomaticAstronomyLocation: Bool
    var astronomyColorID: String
    var astronomyLatitude: Double
    var astronomyLongitude: Double
    var selectedEventCalendarIDs: Set<String>
    var selectedReminderCalendarIDs: Set<String>
    var weekdayOnlyEventCalendarIDs: Set<String>
    var weekdayOnlyReminderCalendarIDs: Set<String>

    static let empty = SettingsDraft(
        includeEvents: true,
        includeAllDayEvents: true,
        includeReminders: true,
        includeWeather: true,
        lookAheadHours: 24,
        alertLeadMinutes: 5,
        nearUpcomingAlternateMinutes: 10,
        concurrentEventRotationSeconds: 30,
        maxListItems: 8,
        enableBlinkAlert: true,
        menuBarFontSize: 13.0,
        useSimplifiedCountdown: true,
        activeEventDisplayMode: .remaining,
        useEventTitleEllipsis: true,
        eventTitleMaxCharacters: 22,
        includeAstronomy: true,
        useAutomaticAstronomyLocation: false,
        astronomyColorID: "blue",
        astronomyLatitude: 18.465,
        astronomyLongitude: -66.106,
        selectedEventCalendarIDs: [],
        selectedReminderCalendarIDs: [],
        weekdayOnlyEventCalendarIDs: [],
        weekdayOnlyReminderCalendarIDs: []
    )
}
