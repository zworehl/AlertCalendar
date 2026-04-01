import AppKit
import SwiftUI

struct SettingsView: View {
    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case feeds = "Feeds"
        case calendars = "Calendars & Reminders"
        case permissions = "Permissions"

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .general:
                return "slider.horizontal.3"
            case .feeds:
                return "sun.max"
            case .calendars:
                return "calendar"
            case .permissions:
                return "lock.shield"
            }
        }
    }

    private enum FeedsSubsection: String, CaseIterable, Identifiable {
        case atmosphere = "Sun & Rain"
        case football = "Football"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .atmosphere:
                return "Sunrise, Sunset & Rain"
            case .football:
                return "Football Fixtures"
            }
        }
    }

    @ObservedObject var monitor: CalendarMonitor

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
    @State private var selectedFeedsSubsection: FeedsSubsection = .atmosphere
    @State private var isRequestingPermissions = false
    @State private var settingsViewportHeight: CGFloat = 0

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

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    activeSettingsContent
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: settingsViewportHeight > 0 ? settingsViewportHeight : nil,
                    alignment: .topLeading
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: SettingsViewportHeightPreferenceKey.self, value: proxy.size.height)
                }
            )

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
        .background(
            SettingsWindowAccessor { window in
                guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
                appDelegate.prepareForSettingsPresentation()
                appDelegate.configureSettingsWindow(window)
            }
        )
        .frame(minWidth: 760, idealWidth: 1040, minHeight: 720, idealHeight: 820)
        .onAppear {
            monitor.refreshAvailableCalendars()
            synchronizeDraftWithStoredSettings(force: true)
            didLoad = true
        }
        .onPreferenceChange(SettingsViewportHeightPreferenceKey.self) { viewportHeight in
            guard abs(settingsViewportHeight - viewportHeight) > 0.5 else { return }
            settingsViewportHeight = viewportHeight
        }
        .onChange(of: availableEventCalendarSignature) { _ in
            synchronizeDraftWithStoredSettings()
        }
        .onChange(of: availableReminderCalendarSignature) { _ in
            synchronizeDraftWithStoredSettings()
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
    private var activeSettingsContent: some View {
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
    private var liveFeedsSettingsContent: some View {
        GroupBox("Live Feeds") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Manage the non-calendar feeds that can appear in Alert Calendar, including sun moments, rain forecast, and football fixtures.")
                    .foregroundStyle(.secondary)

                Picker("Feeds subsection", selection: $selectedFeedsSubsection) {
                    ForEach(FeedsSubsection.allCases) { subsection in
                        Text(subsection.rawValue).tag(subsection)
                    }
                }
                .pickerStyle(.segmented)

                Text("Choose a subsection to focus on one feed at a time.")
                    .font(.caption)
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

    @ViewBuilder
    private var atmosphereFeedsSubsection: some View {
        GroupBox("Sunrise & Sunset") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Toggle("Include sun moments (sunrise/noon/sunset/midnight)", isOn: $draft.includeAstronomy)
                    InfoTipButton(text: "Adds local sunrise, solar noon, sunset, and solar midnight entries calculated from your configured coordinates.")
                }

                Text("These moments are calculated locally using the coordinates configured below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        GroupBox("Rain Forecast") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Toggle("Include rain forecast (Open-Meteo)", isOn: $draft.includeWeather)
                    InfoTipButton(text: "Shows upcoming rain estimate in the menu bar. Uses the same coordinates configured below and the nearest Open-Meteo forecast grid cell.")
                }

                Text("Rain forecasting shares the same location setup used for sun moments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Outside North America and Central Europe, Open-Meteo 15-minute rain data can be interpolated from hourly forecasts, so hyperlocal showers may be missed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        SettingsAstronomySectionView(
            title: "Shared Location & Sun Preview",
            showsCalculatedTimes: true,
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

    @ViewBuilder
    private var footballFeedsSubsection: some View {
        SettingsFootballFixturesSectionView(monitor: monitor)
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

    private func synchronizeDraftWithStoredSettings(force: Bool = false) {
        guard force || (didLoad && !hasUnsavedChanges) else { return }
        resetDraft()
    }

    private var availableEventCalendarSignature: [String] {
        monitor.availableEventCalendars.map(\.id)
    }

    private var availableReminderCalendarSignature: [String] {
        monitor.availableReminderCalendars.map(\.id)
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

    private func persistCalendarSelectionDraft() {
        monitor.defaults.set(Array(draft.selectedEventCalendarIDs), forKey: DefaultsKeys.selectedEventCalendarIDs)
        monitor.defaults.set(Array(draft.selectedReminderCalendarIDs), forKey: DefaultsKeys.selectedReminderCalendarIDs)
        monitor.defaults.set(Array(draft.weekdayOnlyEventCalendarIDs), forKey: DefaultsKeys.weekdayOnlyEventCalendarIDs)
        monitor.defaults.set(Array(draft.weekdayOnlyReminderCalendarIDs), forKey: DefaultsKeys.weekdayOnlyReminderCalendarIDs)
        monitor.refreshNow()
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
            _ = await monitor.requestLocationAuthorizationIfNeeded()
            monitor.refreshAvailableCalendars()
            monitor.refreshNow()
            isRequestingPermissions = false
        }
    }

    private func openPrivacySettings() {
        let deepLinks = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices",
        ]

        for rawValue in deepLinks {
            guard let url = URL(string: rawValue) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        if let settingsAppURL = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(settingsAppURL)
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

private struct SettingsViewportHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SettingsWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> SettingsWindowObserverView {
        SettingsWindowObserverView(onResolve: onResolve)
    }

    func updateNSView(_ nsView: SettingsWindowObserverView, context: Context) {
        nsView.onResolve = onResolve
        nsView.resolveWindowIfNeeded()
    }
}

private final class SettingsWindowObserverView: NSView {
    var onResolve: (NSWindow) -> Void

    init(onResolve: @escaping (NSWindow) -> Void) {
        self.onResolve = onResolve
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveWindowIfNeeded()
    }

    func resolveWindowIfNeeded() {
        guard let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.onResolve(window)
        }
    }
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
