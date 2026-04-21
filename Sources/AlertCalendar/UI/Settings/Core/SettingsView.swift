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

    enum FeedsSubsection: String, CaseIterable, Identifiable {
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

        static func currentLocationAuthorizationStatus() -> CLAuthorizationStatus {
            guard CLLocationManager.locationServicesEnabled() else { return .restricted }
            return CLLocationManager().authorizationStatus
        }

        static func currentContactsAuthorizationStatus() -> CNAuthorizationStatus {
            CNContactStore.authorizationStatus(for: .contacts)
        }
    }

    let monitor: CalendarMonitor

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
    @State var locationAuthorizationStatus = SettingsPermissionKind.currentLocationAuthorizationStatus()
    @State var contactsAuthorizationStatus = SettingsPermissionKind.currentContactsAuthorizationStatus()
    @State var lastRefreshDate: Date?
    @State var permissionButtonsShouldStack = false

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
                    appDelegate.configureSettingsWindow(window)
                },
                onResize: { width in
                    updatePermissionButtonsLayout(windowWidth: width)
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            locationAuthorizationStatus = SettingsPermissionKind.currentLocationAuthorizationStatus()
            contactsAuthorizationStatus = SettingsPermissionKind.currentContactsAuthorizationStatus()
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
}
