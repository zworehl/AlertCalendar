import AppKit
import Combine
import CoreLocation
import EventKit
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
        case atmosphere = "Astronomy"
        case football = "Football"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .atmosphere:
                return "Sun, Moon & Orbit"
            case .football:
                return "Football Fixtures"
            }
        }
    }

    private enum SettingsPermissionKind: String, CaseIterable, Identifiable, Hashable {
        case events
        case reminders
        case location

        var id: String { rawValue }

        var title: String {
            switch self {
            case .events:
                return "Calendar Events"
            case .reminders:
                return "Reminders"
            case .location:
                return "Location"
            }
        }

        var summary: String {
            switch self {
            case .events:
                return "Read events and reveal football fixtures in Calendar."
            case .reminders:
                return "Load reminder due dates and completion status."
            case .location:
                return "Use automatic coordinates for sunrise, sunset, and daylight previews."
            }
        }

        var assetName: String {
            switch self {
            case .events:
                return "permission-calendar"
            case .reminders:
                return "permission-reminders"
            case .location:
                return "permission-location"
            }
        }

        var fallbackSymbolName: String {
            switch self {
            case .events:
                return "calendar.badge.clock"
            case .reminders:
                return "checklist.checked"
            case .location:
                return "location.circle"
            }
        }

        var accentGradient: LinearGradient {
            switch self {
            case .events:
                return LinearGradient(
                    colors: [Color(red: 0.24, green: 0.59, blue: 0.97), Color(red: 0.30, green: 0.78, blue: 0.98)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .reminders:
                return LinearGradient(
                    colors: [Color(red: 0.36, green: 0.77, blue: 0.35), Color(red: 0.66, green: 0.87, blue: 0.34)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .location:
                return LinearGradient(
                    colors: [Color(red: 1.0, green: 0.52, blue: 0.27), Color(red: 0.99, green: 0.76, blue: 0.31)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }

        var privacySettingsDeepLink: String {
            switch self {
            case .events:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
            case .reminders:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
            case .location:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
            }
        }

        static func currentLocationAuthorizationStatus() -> CLAuthorizationStatus {
            guard CLLocationManager.locationServicesEnabled() else { return .restricted }
            return CLLocationManager().authorizationStatus
        }
    }

    let monitor: CalendarMonitor

    @AppStorage(DefaultsKeys.includeEvents) private var includeEvents = true
    @AppStorage(DefaultsKeys.includeAllDayEvents) private var includeAllDayEvents = true
    @AppStorage(DefaultsKeys.includeReminders) private var includeReminders = true
    @AppStorage(DefaultsKeys.lookAheadHours) private var lookAheadHours = 24
    @AppStorage(DefaultsKeys.contextualPreviewLeadMinutes) private var contextualPreviewLeadMinutes = 120
    @AppStorage(DefaultsKeys.menuBarRotationWindowMinutes) private var menuBarRotationWindowMinutes = 60
    @AppStorage(DefaultsKeys.alertLeadMinutes) private var alertLeadMinutes = 5
    @AppStorage(DefaultsKeys.concurrentEventRotationSeconds) private var concurrentEventRotationSeconds = 30
    @AppStorage(DefaultsKeys.maxListItems) private var maxListItems = 8
    @AppStorage(DefaultsKeys.enableBlinkAlert) private var enableBlinkAlert = true
    @AppStorage(DefaultsKeys.menuBarFontSize) private var menuBarFontSize = 13.0
    @AppStorage(DefaultsKeys.useSimplifiedCountdown) private var useSimplifiedCountdown = true
    @AppStorage(DefaultsKeys.activeEventDisplayMode) private var activeEventDisplayModeRaw = ActiveEventDisplayMode.remaining.rawValue
    @AppStorage(DefaultsKeys.useEventTitleEllipsis) private var useEventTitleEllipsis = true
    @AppStorage(DefaultsKeys.eventTitleMaxCharacters) private var eventTitleMaxCharacters = 22
    @AppStorage(DefaultsKeys.includeAstronomy) private var includeAstronomy = true
    @AppStorage(DefaultsKeys.includeSunriseSunset) private var includeSunriseSunset = true
    @AppStorage(DefaultsKeys.includeSolarNoonMidnight) private var includeSolarNoonMidnight = true
    @AppStorage(DefaultsKeys.includeMoonPhases) private var includeMoonPhases = true
    @AppStorage(DefaultsKeys.includeOrbitalHighlights) private var includeOrbitalHighlights = true
    @AppStorage(DefaultsKeys.useAutomaticAstronomyLocation) private var useAutomaticAstronomyLocation = false
    @AppStorage(DefaultsKeys.astronomyColorID) private var astronomyColorID = "blue"
    @AppStorage(DefaultsKeys.astronomyLatitude) private var astronomyLatitude = 18.4655
    @AppStorage(DefaultsKeys.astronomyLongitude) private var astronomyLongitude = -66.1057

    @State private var draft = SettingsDraft.empty
    @State private var didLoad = false
    @State private var selectedTab: SettingsTab = .general
    @State private var selectedFeedsSubsection: FeedsSubsection = .atmosphere
    @State private var activePermissionRequests: Set<SettingsPermissionKind> = []
    @State private var hasEventsAccess = false
    @State private var hasRemindersAccess = false
    @State private var availableEventCalendars: [AvailableCalendar] = []
    @State private var availableReminderCalendars: [AvailableCalendar] = []
    @State private var calendarAccessDescription = "Requesting access..."
    @State private var astronomyLocationStatus = "Manual coordinates"
    @State private var locationAuthorizationStatus = SettingsPermissionKind.currentLocationAuthorizationStatus()
    @State private var lastRefreshDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                Picker("Settings section", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.symbolName)
                            .tag(tab)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 420, alignment: .leading)

                if selectedTab == .feeds {
                    Spacer(minLength: 0)

                    Picker("Feeds subsection", selection: $selectedFeedsSubsection) {
                        ForEach(FeedsSubsection.allCases) { subsection in
                            Text(subsection.rawValue).tag(subsection)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
            }
            .padding(.bottom, 2)

            Group {
                if selectedTab == .feeds, selectedFeedsSubsection == .football {
                    activeSettingsContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            activeSettingsContent
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
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
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                activateSettingsWindowIfNeeded()
            }
        )
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
            activateSettingsWindowIfNeeded()
            monitor.refreshAvailableCalendars()
            synchronizeSettingsStateFromMonitor()
            synchronizeDraftWithStoredSettings(force: true)
            didLoad = true
        }
        .onReceive(monitor.$hasEventsAccess.removeDuplicates()) { value in
            hasEventsAccess = value
        }
        .onReceive(monitor.$hasRemindersAccess.removeDuplicates()) { value in
            hasRemindersAccess = value
        }
        .onReceive(monitor.$availableEventCalendars.removeDuplicates()) { calendars in
            availableEventCalendars = calendars
        }
        .onReceive(monitor.$availableReminderCalendars.removeDuplicates()) { calendars in
            availableReminderCalendars = calendars
        }
        .onReceive(monitor.$calendarAccessDescription.removeDuplicates()) { description in
            calendarAccessDescription = description
        }
        .onReceive(monitor.$astronomyLocationStatus.removeDuplicates()) { status in
            astronomyLocationStatus = status
        }
        .onReceive(monitor.$lastRefreshDate.removeDuplicates()) { date in
            lastRefreshDate = date
        }
        .onChange(of: availableEventCalendarSignature) { _ in
            synchronizeDraftWithStoredSettings()
        }
        .onChange(of: availableReminderCalendarSignature) { _ in
            synchronizeDraftWithStoredSettings()
        }
        .onChange(of: draft.lookAheadHours) { newValue in
            let normalizedDropdownHours = normalizedDropdownWindowHours(newValue)
            if normalizedDropdownHours != draft.lookAheadHours {
                draft.lookAheadHours = normalizedDropdownHours
                return
            }

            let normalizedContextualPreviewLead = normalizedContextualPreviewLeadMinutes(
                draft.contextualPreviewLeadMinutes,
                dropdownWindowHours: normalizedDropdownHours
            )
            if normalizedContextualPreviewLead != draft.contextualPreviewLeadMinutes {
                draft.contextualPreviewLeadMinutes = normalizedContextualPreviewLead
            }

            let normalizedMenuBarMinutes = normalizedMenuBarRotationWindowMinutes(
                draft.menuBarRotationWindowMinutes,
                dropdownWindowHours: normalizedDropdownHours
            )
            if normalizedMenuBarMinutes != draft.menuBarRotationWindowMinutes {
                draft.menuBarRotationWindowMinutes = normalizedMenuBarMinutes
            }
        }
    }

    private func activateSettingsWindowIfNeeded() {
        guard let window = resolvedSettingsWindow() else { return }
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.prepareForSettingsPresentation()
            appDelegate.configureSettingsWindow(window)
        } else {
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func resolvedSettingsWindow() -> NSWindow? {
        let settingsIdentifier = NSUserInterfaceItemIdentifier(WindowMetadata.preferencesID)
        let matchesSettingsWindow: (NSWindow) -> Bool = { window in
            window.identifier == settingsIdentifier || window.title == WindowMetadata.preferencesTitle
        }

        return [NSApp.keyWindow, NSApp.mainWindow]
            .compactMap { $0 }
            .first(where: matchesSettingsWindow)
            ?? NSApp.windows.first(where: { window in
                matchesSettingsWindow(window) && window.isVisible
            })
            ?? NSApp.windows.first(where: matchesSettingsWindow)
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
        let maxMenuBarRotationWindowMinutes = maximumMenuBarRotationWindowMinutes(
            dropdownWindowHours: draft.lookAheadHours
        )
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
                            maximumValue: maxMenuBarRotationWindowMinutes
                        )
                    } onDecrement: {
                        draft.menuBarRotationWindowMinutes = Self.adjustedMenuBarRotationWindowMinutes(
                            currentValue: draft.menuBarRotationWindowMinutes,
                            incrementing: false,
                            maximumValue: maxMenuBarRotationWindowMinutes
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
                    title: "Preview map lead time",
                    valueText: Self.menuBarRotationWindowValueText(
                        minutes: draft.contextualPreviewLeadMinutes
                    ),
                    helpText: "Contextual previews only appear for active events or ones starting inside this window. Applies to calendar events, daylight events, and football fixtures."
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
    private var liveFeedsSettingsContent: some View {
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
    private var atmosphereFeedsSubsection: some View {
        GroupBox("Sun, Moon & Orbit") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Toggle("Include atmosphere moments", isOn: $draft.includeAstronomy)
                    InfoTipButton(text: "Adds local sunrise, solar noon, sunset, solar midnight, estimated lunar phase changes, and estimated perihelion, aphelion, solstice, and equinox entries.")
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        astronomyFeedVisibilityCard
                            .frame(maxWidth: .infinity, alignment: .leading)

                        AstronomyCoordinatesCard(
                            useAutomaticAstronomyLocation: $draft.useAutomaticAstronomyLocation,
                            astronomyLatitude: $draft.astronomyLatitude,
                            astronomyLongitude: $draft.astronomyLongitude,
                            astronomyLocationStatus: astronomyLocationStatus,
                            onDetectNow: detectLocation
                        )
                        .frame(maxWidth: 360, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        astronomyFeedVisibilityCard

                        AstronomyCoordinatesCard(
                            useAutomaticAstronomyLocation: $draft.useAutomaticAstronomyLocation,
                            astronomyLatitude: $draft.astronomyLatitude,
                            astronomyLongitude: $draft.astronomyLongitude,
                            astronomyLocationStatus: astronomyLocationStatus,
                            onDetectNow: detectLocation
                        )
                    }
                }

                Text("The master toggle hides every astronomy feed without clearing the category choices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private var astronomyFeedVisibilityCard: some View {
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
    private var permissionsSettingsContent: some View {
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
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(SettingsPermissionKind.allCases) { permission in
                    permissionActionCard(for: permission)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        GroupBox("Global Shortcuts") {
            VStack(alignment: .leading, spacing: 10) {
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

                Text("macOS only re-shows native permission prompts when the system considers the app eligible. If a permission stays denied, the per-permission Settings button is the reliable path.")
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
            lookAheadHours: normalizedDropdownWindowHours(lookAheadHours),
            contextualPreviewLeadMinutes: normalizedContextualPreviewLeadMinutes(
                contextualPreviewLeadMinutes,
                dropdownWindowHours: normalizedDropdownWindowHours(lookAheadHours)
            ),
            menuBarRotationWindowMinutes: normalizedMenuBarRotationWindowMinutes(
                menuBarRotationWindowMinutes,
                dropdownWindowHours: normalizedDropdownWindowHours(lookAheadHours)
            ),
            alertLeadMinutes: alertLeadMinutes,
            concurrentEventRotationSeconds: concurrentEventRotationSeconds,
            maxListItems: maxListItems,
            enableBlinkAlert: enableBlinkAlert,
            menuBarFontSize: menuBarFontSize,
            useSimplifiedCountdown: useSimplifiedCountdown,
            activeEventDisplayMode: ActiveEventDisplayMode(rawValue: activeEventDisplayModeRaw) ?? .remaining,
            useEventTitleEllipsis: useEventTitleEllipsis,
            eventTitleMaxCharacters: eventTitleMaxCharacters,
            includeAstronomy: includeAstronomy,
            includeSunriseSunset: includeSunriseSunset,
            includeSolarNoonMidnight: includeSolarNoonMidnight,
            includeMoonPhases: includeMoonPhases,
            includeOrbitalHighlights: includeOrbitalHighlights,
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
        availableEventCalendars.map(\.id)
    }

    private var availableReminderCalendarSignature: [String] {
        availableReminderCalendars.map(\.id)
    }

    private func synchronizeSettingsStateFromMonitor() {
        hasEventsAccess = monitor.hasEventsAccess
        hasRemindersAccess = monitor.hasRemindersAccess
        availableEventCalendars = monitor.availableEventCalendars
        availableReminderCalendars = monitor.availableReminderCalendars
        calendarAccessDescription = monitor.calendarAccessDescription
        astronomyLocationStatus = monitor.astronomyLocationStatus
        locationAuthorizationStatus = SettingsPermissionKind.currentLocationAuthorizationStatus()
        lastRefreshDate = monitor.lastRefreshDate
    }

    private func applyDraft() {
        let oldAutoLocation = useAutomaticAstronomyLocation

        includeEvents = draft.includeEvents
        includeAllDayEvents = draft.includeAllDayEvents
        includeReminders = draft.includeReminders
        lookAheadHours = normalizedDropdownWindowHours(draft.lookAheadHours)
        contextualPreviewLeadMinutes = normalizedContextualPreviewLeadMinutes(
            draft.contextualPreviewLeadMinutes,
            dropdownWindowHours: normalizedDropdownWindowHours(draft.lookAheadHours)
        )
        menuBarRotationWindowMinutes = normalizedMenuBarRotationWindowMinutes(
            draft.menuBarRotationWindowMinutes,
            dropdownWindowHours: normalizedDropdownWindowHours(draft.lookAheadHours)
        )
        alertLeadMinutes = draft.alertLeadMinutes
        concurrentEventRotationSeconds = draft.concurrentEventRotationSeconds
        maxListItems = draft.maxListItems
        enableBlinkAlert = draft.enableBlinkAlert
        menuBarFontSize = draft.menuBarFontSize
        useSimplifiedCountdown = draft.useSimplifiedCountdown
        activeEventDisplayModeRaw = draft.activeEventDisplayMode.rawValue
        useEventTitleEllipsis = draft.useEventTitleEllipsis
        eventTitleMaxCharacters = draft.eventTitleMaxCharacters
        includeAstronomy = draft.includeAstronomy
        includeSunriseSunset = draft.includeSunriseSunset
        includeSolarNoonMidnight = draft.includeSolarNoonMidnight
        includeMoonPhases = draft.includeMoonPhases
        includeOrbitalHighlights = draft.includeOrbitalHighlights
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

    private func normalizedDropdownWindowHours(_ value: Int) -> Int {
        max(1, min(168, value))
    }

    private func maximumMenuBarRotationWindowMinutes(dropdownWindowHours: Int) -> Int {
        Self.maximumMenuBarRotationWindowMinutes(
            dropdownWindowHours: normalizedDropdownWindowHours(dropdownWindowHours)
        )
    }

    private func maximumContextualPreviewLeadMinutes(dropdownWindowHours: Int) -> Int {
        Self.maximumContextualPreviewLeadMinutes(
            dropdownWindowHours: normalizedDropdownWindowHours(dropdownWindowHours)
        )
    }

    private func normalizedMenuBarRotationWindowMinutes(_ value: Int, dropdownWindowHours: Int) -> Int {
        Self.normalizedMenuBarRotationWindowMinutes(
            value,
            dropdownWindowHours: normalizedDropdownWindowHours(dropdownWindowHours)
        )
    }

    private func normalizedContextualPreviewLeadMinutes(_ value: Int, dropdownWindowHours: Int) -> Int {
        Self.normalizedContextualPreviewLeadMinutes(
            value,
            dropdownWindowHours: normalizedDropdownWindowHours(dropdownWindowHours)
        )
    }

    @ViewBuilder
    private func permissionActionCard(for permission: SettingsPermissionKind) -> some View {
        let grantState = permissionGrantState(for: permission)
        let isRequesting = activePermissionRequests.contains(permission)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                SettingsPermissionIconView(
                    assetName: permission.assetName,
                    fallbackSymbolName: permission.fallbackSymbolName,
                    gradient: permission.accentGradient
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(permission.title)
                        .font(.headline)
                    Text(permission.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                permissionStatusBadge(for: grantState)
            }

            Text(permissionGrantDescription(for: permission, state: grantState))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    requestPermission(permission)
                } label: {
                    Label(
                        isRequesting ? "Checking..." : permissionPrimaryActionTitle(for: permission, state: grantState),
                        systemImage: isRequesting ? "hourglass" : "arrow.clockwise.circle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRequesting)

                Button {
                    openPrivacySettings(for: permission)
                } label: {
                    Label("Open Settings", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(permissionBorderColor(for: grantState), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func permissionStatusBadge(for state: PermissionGrantState) -> some View {
        Text(state.badgeTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(state.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(state.tint.opacity(0.12))
            )
    }

    private func permissionPrimaryActionTitle(for permission: SettingsPermissionKind, state: PermissionGrantState) -> String {
        switch state {
        case .allowed:
            return permission == .location ? "Check location access" : "Check access again"
        case .notRequested:
            return "Request access"
        case .limited:
            return "Upgrade access"
        case .denied, .restricted:
            return "Check access again"
        }
    }

    private func permissionGrantDescription(for permission: SettingsPermissionKind, state: PermissionGrantState) -> String {
        switch permission {
        case .events:
            switch state {
            case .allowed:
                return "Alert Calendar can read upcoming events and use Calendar-backed football fixture actions."
            case .notRequested:
                return "This prompt has not been granted yet. Request it here to load events into the app."
            case .limited:
                return "Calendar access is only partially granted. Open Settings and switch Alert Calendar to full access so events can be read."
            case .denied:
                return "macOS denied event access. Use Open Settings to re-enable Calendar access for Alert Calendar."
            case .restricted:
                return "Event access is restricted by macOS or device policy."
            }
        case .reminders:
            switch state {
            case .allowed:
                return "Reminder due dates and completion actions are available to the app."
            case .notRequested:
                return "This prompt has not been granted yet. Request it here to include reminders in the dropdown."
            case .limited:
                return "Reminders access is only partially granted. Open Settings and switch Alert Calendar to full access so reminders can be read."
            case .denied:
                return "macOS denied reminder access. Use Open Settings to re-enable Reminders access for Alert Calendar."
            case .restricted:
                return "Reminder access is restricted by macOS or device policy."
            }
        case .location:
            switch state {
            case .allowed:
                return astronomyLocationStatus
            case .notRequested:
                return "Location has not been requested yet. Grant it to support automatic astronomy coordinates and daylight maps."
            case .limited:
                return astronomyLocationStatus
            case .denied:
                return "Location access is denied. Use Open Settings to allow location for Alert Calendar."
            case .restricted:
                return "Location Services are unavailable or restricted on this Mac."
            }
        }
    }

    private func permissionBorderColor(for state: PermissionGrantState) -> Color {
        state.tint.opacity(0.24)
    }

    private func permissionGrantState(for permission: SettingsPermissionKind) -> PermissionGrantState {
        switch permission {
        case .events:
            if hasEventsAccess || Self.isGrantedEventKitAuthorizationStatus(EKEventStore.authorizationStatus(for: .event)) {
                return .allowed
            }
            return Self.permissionGrantState(for: EKEventStore.authorizationStatus(for: .event))
        case .reminders:
            if hasRemindersAccess || Self.isGrantedEventKitAuthorizationStatus(EKEventStore.authorizationStatus(for: .reminder)) {
                return .allowed
            }
            return Self.permissionGrantState(for: EKEventStore.authorizationStatus(for: .reminder))
        case .location:
            return Self.permissionGrantState(for: locationAuthorizationStatus)
        }
    }

    private func requestPermission(_ permission: SettingsPermissionKind) {
        guard !activePermissionRequests.contains(permission) else { return }
        activePermissionRequests.insert(permission)

        Task { @MainActor in
            defer { activePermissionRequests.remove(permission) }

            switch permission {
            case .events:
                monitor.hasEventsAccess = await monitor.requestEventsAccess()
                monitor.updateAccessDescription()
            case .reminders:
                monitor.hasRemindersAccess = await monitor.requestRemindersAccess()
                monitor.updateAccessDescription()
            case .location:
                let status = await monitor.requestLocationAuthorizationIfNeeded()
                locationAuthorizationStatus = status
                if monitor.defaults.bool(forKey: DefaultsKeys.useAutomaticAstronomyLocation),
                   Self.permissionGrantState(for: status) == .allowed {
                    monitor.refreshAstronomyCoordinatesFromSystem()
                }
            }

            refreshPermissionStatuses()
        }
    }

    private func refreshPermissionStatuses() {
        monitor.refreshAvailableCalendars()
        synchronizeSettingsStateFromMonitor()
        monitor.refreshNow()
    }

    private func openPrivacySettings() {
        let deepLinks = SettingsPermissionKind.allCases.map(\.privacySettingsDeepLink)

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

    private func openPrivacySettings(for permission: SettingsPermissionKind) {
        guard let url = URL(string: permission.privacySettingsDeepLink) else {
            openPrivacySettings()
            return
        }

        if !NSWorkspace.shared.open(url) {
            openPrivacySettings()
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

    nonisolated static func durationValueText(value: Int, singular: String, plural: String) -> String {
        let normalizedValue = max(0, value)
        let unit = normalizedValue == 1 ? singular : plural
        return "\(normalizedValue) \(unit)"
    }

    nonisolated static func menuBarRotationWindowValueText(minutes: Int) -> String {
        let normalizedMinutes = max(1, minutes)
        if normalizedMinutes < 60 {
            return durationValueText(
                value: normalizedMinutes,
                singular: "minute",
                plural: "minutes"
            )
        }

        let hours = normalizedMinutes / 60
        let remainingMinutes = normalizedMinutes % 60

        if remainingMinutes == 0 {
            return durationValueText(
                value: hours,
                singular: "hour",
                plural: "hours"
            )
        }

        return "\(durationValueText(value: hours, singular: "hour", plural: "hours")) \(durationValueText(value: remainingMinutes, singular: "minute", plural: "minutes"))"
    }

    nonisolated static func maximumMenuBarRotationWindowMinutes(dropdownWindowHours: Int) -> Int {
        let normalizedDropdownHours = max(1, min(168, dropdownWindowHours))
        if normalizedDropdownHours == 1 {
            return 55
        }

        return min(720, (normalizedDropdownHours - 1) * 60)
    }

    nonisolated static func maximumContextualPreviewLeadMinutes(dropdownWindowHours: Int) -> Int {
        let normalizedDropdownHours = max(1, min(168, dropdownWindowHours))
        return normalizedDropdownHours * 60
    }

    nonisolated static func normalizedMenuBarRotationWindowMinutes(_ value: Int, dropdownWindowHours: Int) -> Int {
        let upperBound = maximumMenuBarRotationWindowMinutes(dropdownWindowHours: dropdownWindowHours)
        let fallback = min(60, upperBound)
        let candidate = value > 0 ? value : fallback
        let clamped = max(5, min(upperBound, candidate))

        if clamped < 60 {
            return Int((Double(clamped) / 5.0).rounded()) * 5
        }

        return Int((Double(clamped) / 60.0).rounded()) * 60
    }

    nonisolated static func normalizedContextualPreviewLeadMinutes(_ value: Int, dropdownWindowHours: Int) -> Int {
        let upperBound = maximumContextualPreviewLeadMinutes(dropdownWindowHours: dropdownWindowHours)
        let fallback = min(120, upperBound)
        let candidate = value > 0 ? value : fallback
        let clamped = max(60, min(upperBound, candidate))
        return Int((Double(clamped) / 60.0).rounded()) * 60
    }

    nonisolated static func adjustedMenuBarRotationWindowMinutes(
        currentValue: Int,
        incrementing: Bool,
        maximumValue: Int
    ) -> Int {
        let normalizedCurrentValue = max(5, min(maximumValue, currentValue))

        if incrementing {
            if normalizedCurrentValue < 60 {
                return min(maximumValue, normalizedCurrentValue + 5)
            }
            return min(maximumValue, normalizedCurrentValue + 60)
        }

        if normalizedCurrentValue <= 60 {
            return max(5, normalizedCurrentValue - 5)
        }

        return max(60, normalizedCurrentValue - 60)
    }

    private static func isGrantedEventKitAuthorizationStatus(_ status: EKAuthorizationStatus) -> Bool {
        if status == .authorized {
            return true
        }

        if #available(macOS 14.0, *) {
            if status == .fullAccess {
                return true
            }

            if status == .writeOnly {
                return false
            }
        }

        if status == .notDetermined || status == .denied || status == .restricted {
            return false
        }

        return false
    }

    private static func permissionGrantState(for status: EKAuthorizationStatus) -> PermissionGrantState {
        if status == .authorized {
            return .allowed
        }

        if #available(macOS 14.0, *) {
            if status == .fullAccess {
                return .allowed
            }

            if status == .writeOnly {
                return .limited
            }
        }

        if status == .notDetermined {
            return .notRequested
        }

        if status == .denied {
            return .denied
        }

        if status == .restricted {
            return .restricted
        }

        return .restricted
    }

    private static func permissionGrantState(for status: CLAuthorizationStatus) -> PermissionGrantState {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse, .authorized:
            return .allowed
        case .notDetermined:
            return .notRequested
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
    }

}

private enum PermissionGrantState: String, CaseIterable {
    case allowed
    case notRequested
    case limited
    case denied
    case restricted

    var badgeTitle: String {
        switch self {
        case .allowed:
            return "Allowed"
        case .notRequested:
            return "Not Requested"
        case .limited:
            return "Limited"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        }
    }

    var tint: Color {
        switch self {
        case .allowed:
            return Color(red: 0.24, green: 0.72, blue: 0.33)
        case .notRequested:
            return Color(red: 0.24, green: 0.59, blue: 0.97)
        case .limited:
            return Color(red: 1.0, green: 0.62, blue: 0.21)
        case .denied:
            return Color(red: 0.92, green: 0.31, blue: 0.28)
        case .restricted:
            return Color.secondary
        }
    }
}

private struct SettingsPermissionIconView: View {
    let assetName: String
    let fallbackSymbolName: String
    let gradient: LinearGradient

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(gradient.opacity(0.18))

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)

            if let image = Self.assetImage(named: assetName) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(10)
            } else {
                Image(systemName: fallbackSymbolName)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 56, height: 56)
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    private static func assetImage(named name: String) -> NSImage? {
        let bundle = Bundle.module
        let candidateURLs = [
            bundle.url(forResource: name, withExtension: "svg"),
            bundle.url(forResource: name, withExtension: "svg", subdirectory: "Resources/Images"),
        ]

        for url in candidateURLs.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: url) {
                image.isTemplate = false
                return image
            }
        }

        return nil
    }
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
    private weak var lastResolvedWindow: NSWindow?

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
        lastResolvedWindow = nil
        resolveWindowIfNeeded(force: true)
    }

    func resolveWindowIfNeeded(force: Bool = false) {
        guard let window else { return }
        guard force || lastResolvedWindow !== window else { return }
        lastResolvedWindow = window
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
    var lookAheadHours: Int
    var contextualPreviewLeadMinutes: Int
    var menuBarRotationWindowMinutes: Int
    var alertLeadMinutes: Int
    var concurrentEventRotationSeconds: Int
    var maxListItems: Int
    var enableBlinkAlert: Bool
    var menuBarFontSize: Double
    var useSimplifiedCountdown: Bool
    var activeEventDisplayMode: ActiveEventDisplayMode
    var useEventTitleEllipsis: Bool
    var eventTitleMaxCharacters: Int
    var includeAstronomy: Bool
    var includeSunriseSunset: Bool
    var includeSolarNoonMidnight: Bool
    var includeMoonPhases: Bool
    var includeOrbitalHighlights: Bool
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
        lookAheadHours: 24,
        contextualPreviewLeadMinutes: 120,
        menuBarRotationWindowMinutes: 60,
        alertLeadMinutes: 5,
        concurrentEventRotationSeconds: 30,
        maxListItems: 8,
        enableBlinkAlert: true,
        menuBarFontSize: 13.0,
        useSimplifiedCountdown: true,
        activeEventDisplayMode: .remaining,
        useEventTitleEllipsis: true,
        eventTitleMaxCharacters: 22,
        includeAstronomy: true,
        includeSunriseSunset: true,
        includeSolarNoonMidnight: true,
        includeMoonPhases: true,
        includeOrbitalHighlights: true,
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
