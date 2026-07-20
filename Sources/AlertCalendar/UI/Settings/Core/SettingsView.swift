import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

struct SettingsView: View {
    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case feeds = "Feeds"
        case calendars = "Calendars"
        case integrations = "Integrations"
        case access = "Access"

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .general:
                return "slider.horizontal.3"
            case .feeds:
                return "sun.max"
            case .calendars:
                return "calendar"
            case .integrations:
                return "puzzlepiece.extension"
            case .access:
                return "lock.shield"
            }
        }
    }

    enum FeedsSubsection: String, CaseIterable, Identifiable {
        case atmosphere = "Atmosphere"
        case football = "Football"
        case gameSales = "Game Sales"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .atmosphere:
                return "Atmosphere"
            case .football:
                return "Football Fixtures"
            case .gameSales:
                return "Game Sales"
            }
        }

        var symbolName: String {
            switch self {
            case .atmosphere:
                return "sun.max"
            case .football:
                return "sportscourt"
            case .gameSales:
                return "gamecontroller.fill"
            }
        }
    }

    enum SettingsPermissionKind: String, CaseIterable, Identifiable, Hashable {
        case events
        case reminders
        case location
        case contacts

        var id: String { rawValue }

        var title: String {
            switch self {
            case .events:
                return "Calendar Events"
            case .reminders:
                return "Reminders"
            case .location:
                return "Location"
            case .contacts:
                return "Contacts"
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
            case .contacts:
                return "Match organizers and invitees with Contacts to show names and photos in meeting previews."
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
            case .contacts:
                return "person.crop.circle"
            }
        }

        var appIconPath: String {
            switch self {
            case .events:
                return "/System/Applications/Calendar.app"
            case .reminders:
                return "/System/Applications/Reminders.app"
            case .location:
                return "/System/Applications/Maps.app"
            case .contacts:
                return "/System/Applications/Contacts.app"
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
            case .contacts:
                return LinearGradient(
                    colors: [Color(red: 0.43, green: 0.58, blue: 0.98), Color(red: 0.42, green: 0.81, blue: 0.92)],
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
            case .contacts:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts"
            }
        }

        @MainActor private static let authorizationCacheInterval: TimeInterval = 30
        @MainActor private static var cachedEventAuthorizationStatus: EKAuthorizationStatus?
        @MainActor private static var cachedEventAuthorizationStatusDate: Date?
        @MainActor private static var cachedReminderAuthorizationStatus: EKAuthorizationStatus?
        @MainActor private static var cachedReminderAuthorizationStatusDate: Date?
        @MainActor private static let locationAuthorizationManager = CLLocationManager()
        @MainActor private static var cachedLocationAuthorizationStatus: CLAuthorizationStatus?
        @MainActor private static var cachedLocationAuthorizationStatusDate: Date?
        @MainActor private static var cachedContactsAuthorizationStatus: CNAuthorizationStatus?
        @MainActor private static var cachedContactsAuthorizationStatusDate: Date?

        @MainActor static func currentEventAuthorizationStatus(
            now: Date = Date(),
            forceRefresh: Bool = false
        ) -> EKAuthorizationStatus {
            if !forceRefresh,
               let cachedEventAuthorizationStatus,
               let cachedEventAuthorizationStatusDate,
               now.timeIntervalSince(cachedEventAuthorizationStatusDate) < authorizationCacheInterval {
                return cachedEventAuthorizationStatus
            }

            let status = EKEventStore.authorizationStatus(for: .event)
            cachedEventAuthorizationStatus = status
            cachedEventAuthorizationStatusDate = now
            return status
        }

        @MainActor static func currentReminderAuthorizationStatus(
            now: Date = Date(),
            forceRefresh: Bool = false
        ) -> EKAuthorizationStatus {
            if !forceRefresh,
               let cachedReminderAuthorizationStatus,
               let cachedReminderAuthorizationStatusDate,
               now.timeIntervalSince(cachedReminderAuthorizationStatusDate) < authorizationCacheInterval {
                return cachedReminderAuthorizationStatus
            }

            let status = EKEventStore.authorizationStatus(for: .reminder)
            cachedReminderAuthorizationStatus = status
            cachedReminderAuthorizationStatusDate = now
            return status
        }

        @MainActor static func currentLocationAuthorizationStatus(
            now: Date = Date(),
            forceRefresh: Bool = false
        ) -> CLAuthorizationStatus {
            if !forceRefresh,
               let cachedLocationAuthorizationStatus,
               let cachedLocationAuthorizationStatusDate,
               now.timeIntervalSince(cachedLocationAuthorizationStatusDate) < authorizationCacheInterval {
                return cachedLocationAuthorizationStatus
            }

            let status: CLAuthorizationStatus
            if CLLocationManager.locationServicesEnabled() {
                status = locationAuthorizationManager.authorizationStatus
            } else {
                status = .restricted
            }

            updateCachedLocationAuthorizationStatus(status, now: now)
            return status
        }

        @MainActor static func updateCachedLocationAuthorizationStatus(
            _ status: CLAuthorizationStatus,
            now: Date = Date()
        ) {
            cachedLocationAuthorizationStatus = status
            cachedLocationAuthorizationStatusDate = now
        }

        @MainActor static func currentContactsAuthorizationStatus(
            now: Date = Date(),
            forceRefresh: Bool = false
        ) -> CNAuthorizationStatus {
            if !forceRefresh,
               let cachedContactsAuthorizationStatus,
               let cachedContactsAuthorizationStatusDate,
               now.timeIntervalSince(cachedContactsAuthorizationStatusDate) < authorizationCacheInterval {
                return cachedContactsAuthorizationStatus
            }

            let status = CNContactStore.authorizationStatus(for: .contacts)
            updateCachedContactsAuthorizationStatus(status, now: now)
            return status
        }

        @MainActor static func updateCachedContactsAuthorizationStatus(
            _ status: CNAuthorizationStatus,
            now: Date = Date()
        ) {
            cachedContactsAuthorizationStatus = status
            cachedContactsAuthorizationStatusDate = now
        }
    }

    enum SettingsIntegrationKind: String, CaseIterable, Identifiable {
        case slackStatusSync

        var id: String { rawValue }

        var title: String {
            switch self {
            case .slackStatusSync:
                return "Slack Status Sync"
            }
        }

        var summary: String {
            switch self {
            case .slackStatusSync:
                return "Publish customizable Slack statuses before and during selected calendar events."
            }
        }

        var fallbackSymbolName: String {
            switch self {
            case .slackStatusSync:
                return "message.badge.waveform"
            }
        }

        var appIconPath: String {
            switch self {
            case .slackStatusSync:
                return "/Applications/Slack.app"
            }
        }

        var accentGradient: LinearGradient {
            switch self {
            case .slackStatusSync:
                return LinearGradient(
                    colors: [Color(red: 0.26, green: 0.76, blue: 0.52), Color(red: 0.91, green: 0.23, blue: 0.47)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    let monitor: CalendarMonitor

    @StateObject var settingsWindowCloseGuard = SettingsWindowCloseGuard()
    @State var draft = SettingsDraft.empty
    @State var didLoad = false
    @State var selectedTab: SettingsTab = .general
    @State var selectedFeedsSubsection: FeedsSubsection = .atmosphere
    @State var activePermissionRequests: Set<SettingsPermissionKind> = []
    @State var hasEventsAccess = false
    @State var hasRemindersAccess = false
    @State var availableEventCalendars: [AvailableCalendar] = []
    @State var availableReminderCalendars: [AvailableCalendar] = []
    @State var calendarAccessDescription = "Requesting access..."
    @State var astronomyLocationStatus = "Manual coordinates"
    @State var eventAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    @State var reminderAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    @State var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @State var contactsAuthorizationStatus: CNAuthorizationStatus = .notDetermined
    @State var lastRefreshDate: Date?
    @State var refreshDiagnostics = CalendarMonitorRefreshDiagnostics()
    @State var externalFeedDiagnostics = ExternalFeedDiagnostics()
    @State var isShowingPermissionDiagnostics = false
    @State var slackUserTokenDraft = ""
    @State var slackConnections: [SlackConnection] = []
    @State var slackConnectErrorMessage: String?
    @State var slackConnectionStatusMessage: String?
    @State var slackRuntimeStatusDescription: String?
    @State var isRefreshingSlackConnectionMetadata = false
    @State var didAttemptSlackConnectionMetadataRefresh = false
    @State var draggingSlackStatusRuleID: String?
    @State var isShowingSlackConnectionManagement = false
    @State var slackStatusRulesColumnWidth: CGFloat = 0
    @State var installedMeetingBrowsers: [MeetingBrowserKind] = MeetingBrowserCatalog.installedBrowsers()
    @State var meetingBrowserProfilesByBrowser: [MeetingBrowserKind: [MeetingBrowserProfileOption]] = MeetingBrowserProfileStore.profilesByBrowser(
        for: MeetingBrowserCatalog.installedBrowsers()
    )
    @State var settingsWindowWidth: CGFloat = 1040

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsNavigationControls
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
                    monitor.refreshNow(reason: .manual)
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
            SettingsWindowAccessor(
                onResolve: { window in
                    guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
                    appDelegate.prepareForSettingsPresentation()
                    appDelegate.configureSettingsWindow(window, closeGuard: settingsWindowCloseGuard)
                },
                onResize: { width in
                    settingsWindowWidth = width
                }
            )
        )
        .frame(minWidth: 760, idealWidth: 1040, minHeight: 720, idealHeight: 820)
        .onAppear {
            activateSettingsWindowIfNeeded()
            monitor.refreshAvailableCalendars()
            synchronizeSettingsStateFromMonitor()
            synchronizeDraftWithStoredSettings(force: true)
            didLoad = true
            configureSettingsWindowCloseGuard()
            refreshSlackConnectionMetadataIfNeeded()
        }
        .onDisappear {
            settingsWindowCloseGuard.clear()
        }
        .onChange(of: hasUnsavedChanges) { hasChanges in
            settingsWindowCloseGuard.hasUnsavedChanges = hasChanges
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
        .onReceive(monitor.$slackRuntimeStatusDescription.removeDuplicates()) { description in
            slackRuntimeStatusDescription = description
        }
        .onReceive(monitor.$astronomyLocationStatus.removeDuplicates()) { status in
            astronomyLocationStatus = status
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            eventAuthorizationStatus = SettingsPermissionKind.currentEventAuthorizationStatus()
            reminderAuthorizationStatus = SettingsPermissionKind.currentReminderAuthorizationStatus()
            locationAuthorizationStatus = SettingsPermissionKind.currentLocationAuthorizationStatus()
            contactsAuthorizationStatus = SettingsPermissionKind.currentContactsAuthorizationStatus()
        }
        .onReceive(monitor.$lastRefreshDate.removeDuplicates()) { date in
            lastRefreshDate = date
        }
        .onReceive(monitor.$refreshDiagnostics.removeDuplicates()) { diagnostics in
            refreshDiagnostics = diagnostics
        }
        .onReceive(monitor.$externalFeedDiagnostics.removeDuplicates()) { diagnostics in
            externalFeedDiagnostics = diagnostics
        }
        .onReceive(monitor.$slackConnectionStatusMessage.removeDuplicates()) { message in
            slackConnectionStatusMessage = message
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            synchronizeSettingsStateFromMonitor()
            synchronizeDraftWithStoredSettings()
        }
        .onChange(of: availableEventCalendarSignature) { _ in
            synchronizeDraftWithStoredSettings()
        }
        .onChange(of: availableReminderCalendarSignature) { _ in
            synchronizeDraftWithStoredSettings()
        }
        .onChange(of: draft.lookAheadHours) { newValue in
            let normalizedDropdownHours = AppSettingsRules.normalizedDropdownWindowHours(newValue)
            if normalizedDropdownHours != draft.lookAheadHours {
                draft.lookAheadHours = normalizedDropdownHours
                return
            }

            let normalizedContextualPreviewLead = AppSettingsRules.normalizedContextualPreviewLeadMinutes(
                draft.contextualPreviewLeadMinutes,
                dropdownWindowHours: normalizedDropdownHours
            )
            if normalizedContextualPreviewLead != draft.contextualPreviewLeadMinutes {
                draft.contextualPreviewLeadMinutes = normalizedContextualPreviewLead
            }

            let normalizedMenuBarMinutes = AppSettingsRules.normalizedMenuBarRotationWindowMinutes(
                draft.menuBarRotationWindowMinutes,
                dropdownWindowHours: normalizedDropdownHours
            )
            if normalizedMenuBarMinutes != draft.menuBarRotationWindowMinutes {
                draft.menuBarRotationWindowMinutes = normalizedMenuBarMinutes
            }
        }
    }
}
