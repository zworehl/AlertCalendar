import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

struct SettingsView: View {
    let monitor: CalendarMonitor

    @StateObject var settingsWindowCloseGuard = SettingsWindowCloseGuard()
    @State var draft = SettingsDraft.empty
    @State var pendingChanges = SettingsPendingChanges()
    @State var isApplyingChanges = false
    @State var didLoad = false
    @AppStorage(SettingsNavigationPersistence.selectedTabKey)
    var selectedTab: SettingsTab = .general
    @AppStorage(SettingsNavigationPersistence.selectedFeedsSubsectionKey)
    var selectedFeedsSubsection: FeedsSubsection = .atmosphere
    @State var settingsSearchQuery = ""
    @State var activePermissionRequests: Set<SettingsPermissionKind> = []
    @State var permissionActionMessages: [SettingsPermissionKind: String] = [:]
    @State var hasEventsAccess = false
    @State var hasRemindersAccess = false
    @State var availableEventCalendars: [AvailableCalendar] = []
    @State var availableReminderCalendars: [AvailableCalendar] = []
    @State var calendarAccessDescription = "Requesting access..."
    @State var calendarAlertRuleStatusDescription: String?
    @State var astronomyLocationStatus = "Manual coordinates"
    @State var eventAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    @State var reminderAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    @State var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @State var contactsAuthorizationStatus: CNAuthorizationStatus = .notDetermined
    @State var lastRefreshDate: Date?
    @State var lastGameSalesRefreshDate: Date?
    @State var googleHolidayLastRefreshDate: Date?
    @State var lastFootballRefreshDate: Date?
    @State var lastAstronomyLocationRefreshDate: Date?
    @State var lastSlackStatusSyncDate: Date?
    @State var refreshDiagnostics = CalendarMonitorRefreshDiagnostics()
    @State var isManualSettingsRefreshInProgress = false
    @State var externalFeedDiagnostics = ExternalFeedDiagnostics()
    @State var isShowingPermissionDiagnostics = false
    @State var slackUserTokenDraft = ""
    @State var slackConnections: [SlackConnection] = []
    @State var slackConnectErrorMessage: String?
    @State var slackConnectionStatusMessage: String?
    @State var slackRuntimeStatusDescription: String?
    @State var agendaSummaryAvailability = AgendaSummaryAvailability.unsupportedSystem
    @State var agendaSummaryGenerationErrorDescription: String?
    @State var isRefreshingSlackConnectionMetadata = false
    @State var didAttemptSlackConnectionMetadataRefresh = false
    @State var draggingSlackStatusRuleID: String?
    @State var isShowingSlackConnectionManagement = false
    @State var slackStatusRulesColumnWidth: CGFloat = 0
    @State var installedMeetingBrowsers: [MeetingBrowserKind] = MeetingBrowserCatalog.installedBrowsers()
    @State var meetingBrowserProfileCatalog: MeetingBrowserProfileCatalog = MeetingBrowserProfileStore.catalog(
        for: MeetingBrowserCatalog.installedBrowsers()
    )
    @State var browserProfileAuthorizationErrorMessage: String?
    @State var settingsWindowWidth: CGFloat = 976
    @State var settingsColumnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        settingsNavigationLayout
        .disabled(isApplyingChanges)
        .environment(\.controlSize, .regular)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                activateSettingsWindowIfNeeded()
            }
        )
        .background(
            SettingsWindowAccessor(
                onResolve: { window in
                    guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
                    appDelegate.prepareForSettingsPresentation()
                    appDelegate.configureSettingsWindow(window, closeGuard: settingsWindowCloseGuard)
                }
            )
        )
        .frame(minWidth: 980, idealWidth: 1240, minHeight: 720, idealHeight: 840)
        .onAppear {
            activateSettingsWindowIfNeeded()
            monitor.refreshAgendaSummaryAvailability()
            agendaSummaryAvailability = monitor.agendaSummaryAvailability
            agendaSummaryGenerationErrorDescription = monitor.agendaSummaryGenerationErrorDescription
            monitor.refreshAvailableCalendars()
            synchronizeSettingsStateFromMonitor(refreshBrowserProfiles: true)
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
        .onReceive(monitor.$calendarAlertRuleStatusDescription.removeDuplicates()) { description in
            calendarAlertRuleStatusDescription = description
        }
        .onReceive(monitor.$slackRuntimeStatusDescription.removeDuplicates()) { description in
            slackRuntimeStatusDescription = description
        }
        .onReceive(monitor.$agendaSummaryAvailability.removeDuplicates()) { availability in
            agendaSummaryAvailability = availability
        }
        .onReceive(monitor.$agendaSummaryGenerationErrorDescription.removeDuplicates()) { description in
            agendaSummaryGenerationErrorDescription = description
        }
        .onReceive(monitor.$astronomyLocationStatus.removeDuplicates()) { status in
            astronomyLocationStatus = status
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            monitor.refreshAgendaSummaryAvailability()
            eventAuthorizationStatus = SettingsPermissionKind.currentEventAuthorizationStatus()
            reminderAuthorizationStatus = SettingsPermissionKind.currentReminderAuthorizationStatus()
            locationAuthorizationStatus = SettingsPermissionKind.currentLocationAuthorizationStatus()
            contactsAuthorizationStatus = SettingsPermissionKind.currentContactsAuthorizationStatus()
            refreshMeetingBrowserProfiles()
        }
        .onReceive(monitor.$lastRefreshDate.removeDuplicates()) { date in
            lastRefreshDate = date
        }
        .onReceive(monitor.$lastGameSalesRefreshDate.removeDuplicates()) { date in
            lastGameSalesRefreshDate = date
        }
        .onReceive(monitor.$googleHolidayLastRefreshDate.removeDuplicates()) { date in
            googleHolidayLastRefreshDate = date
        }
        .onReceive(monitor.$lastFootballRefreshDate.removeDuplicates()) { date in
            lastFootballRefreshDate = date
        }
        .onReceive(monitor.$lastAstronomyLocationRefreshDate.removeDuplicates()) { date in
            lastAstronomyLocationRefreshDate = date
        }
        .onReceive(monitor.$lastSlackStatusSyncDate.removeDuplicates()) { date in
            lastSlackStatusSyncDate = date
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
        .onReceive(
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
        ) { _ in
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
        .onPreferenceChange(SettingsDetailWidthPreferenceKey.self) { width in
            guard width > 0 else { return }
            settingsWindowWidth = width
        }
    }
}
