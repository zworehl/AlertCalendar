import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    func integrationDescription(for _: SettingsIntegrationKind) -> String {
        slackIntegrationDescription()
    }

    func permissionPrimaryButton(
        for permission: SettingsPermissionKind,
        grantState: PermissionGrantState,
        isRequesting: Bool
    ) -> some View {
        Button {
            performPrimaryPermissionAction(permission, grantState: grantState)
        } label: {
            Label(
                isRequesting ? "Checking..." : permissionPrimaryActionTitle(for: permission, state: grantState),
                systemImage: isRequesting ? "hourglass" : permissionPrimaryActionSymbol(for: grantState)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(isRequesting)
    }

    func permissionSettingsButton(for permission: SettingsPermissionKind) -> some View {
        Button {
            openPrivacySettings(for: permission)
        } label: {
            Label("Open Settings…", systemImage: "gearshape")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    @ViewBuilder
    func permissionStatusBadge(for state: PermissionGrantState) -> some View {
        cardStatusBadge(
            SettingsCardBadgeState(title: state.badgeTitle, tint: state.tint)
        )
    }

    @ViewBuilder
    func cardStatusBadge(_ state: SettingsCardBadgeState) -> some View {
        SettingsStatusBadge(title: state.title, tint: state.tint)
    }

    func permissionPrimaryActionTitle(for permission: SettingsPermissionKind, state: PermissionGrantState) -> String {
        switch state {
        case .allowed:
            return "Refresh status"
        case .notRequested:
            return "Request access"
        case .limited:
            return permission == .location ? "Check access" : "Upgrade access"
        case .denied, .restricted:
            return "Open Settings…"
        }
    }

    func permissionPrimaryActionSymbol(for state: PermissionGrantState) -> String {
        switch state {
        case .allowed:
            return "arrow.clockwise.circle"
        case .notRequested:
            return "hand.raised.circle"
        case .limited:
            return "arrow.up.circle"
        case .denied, .restricted:
            return "gearshape"
        }
    }

    func performPrimaryPermissionAction(
        _ permission: SettingsPermissionKind,
        grantState: PermissionGrantState
    ) {
        switch grantState {
        case .notRequested, .limited:
            requestPermission(permission)
        case .denied, .restricted:
            permissionActionMessages[permission] = "macOS will not show the permission prompt again. Enable access for AlertCalendar in System Settings."
            openPrivacySettings(for: permission)
        case .allowed:
            permissionActionMessages[permission] = nil
            refreshPermissionStatuses(forceRefresh: true)
        }
    }

    func permissionGrantDescription(for permission: SettingsPermissionKind, state: PermissionGrantState) -> String {
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
                return "Location access is available for automatic astronomy coordinates."
            case .notRequested:
                return "Location has not been requested yet. Grant it to support automatic astronomy coordinates and daylight maps, or enter coordinates manually below."
            case .limited:
                return "Location access is available for automatic astronomy coordinates."
            case .denied:
                return "Location access is denied. Use Open Settings to allow location for Alert Calendar, or switch to manual coordinates below."
            case .restricted:
                return "Location Services are unavailable or restricted on this Mac. Manual coordinates are still available below."
            }
        case .contacts:
            switch state {
            case .allowed:
                return "Meeting previews can use contact names and organizer photos from the Contacts app."
            case .notRequested:
                return "Contacts access has not been requested yet. Grant it to enrich invitee names and organizer avatars in meeting previews."
            case .limited:
                return "Contacts access is limited. Open Settings and allow full Contacts access for Alert Calendar."
            case .denied:
                return "Contacts access is denied. Use Open Settings to allow Contacts for Alert Calendar and show names or avatars in meeting previews."
            case .restricted:
                return "Contacts access is restricted by macOS or device policy."
            }
        }
    }

    func permissionBorderColor(for state: PermissionGrantState) -> Color {
        state.tint.opacity(0.24)
    }

    func permissionGrantState(for permission: SettingsPermissionKind) -> PermissionGrantState {
        switch permission {
        case .events:
            if hasEventsAccess || Self.isGrantedEventKitAuthorizationStatus(eventAuthorizationStatus) {
                return .allowed
            }
            return Self.permissionGrantState(for: eventAuthorizationStatus)
        case .reminders:
            if hasRemindersAccess || Self.isGrantedEventKitAuthorizationStatus(reminderAuthorizationStatus) {
                return .allowed
            }
            return Self.permissionGrantState(for: reminderAuthorizationStatus)
        case .location:
            return Self.permissionGrantState(for: locationAuthorizationStatus)
        case .contacts:
            return Self.permissionGrantState(for: contactsAuthorizationStatus)
        }
    }

    func requestPermission(_ permission: SettingsPermissionKind) {
        guard !activePermissionRequests.contains(permission) else { return }
        activePermissionRequests.insert(permission)
        permissionActionMessages[permission] = nil

        Task { @MainActor in
            defer { activePermissionRequests.remove(permission) }

            let granted: Bool
            switch permission {
            case .events:
                granted = await monitor.requestEventsAccess()
                monitor.hasEventsAccess = granted
                eventAuthorizationStatus = SettingsPermissionKind.currentEventAuthorizationStatus(forceRefresh: true)
                monitor.updateAccessDescription()
            case .reminders:
                granted = await monitor.requestRemindersAccess()
                monitor.hasRemindersAccess = granted
                reminderAuthorizationStatus = SettingsPermissionKind.currentReminderAuthorizationStatus(forceRefresh: true)
                monitor.updateAccessDescription()
            case .location:
                let status = await monitor.requestLocationAuthorizationIfNeeded()
                granted = Self.permissionGrantState(for: status) == .allowed
                locationAuthorizationStatus = status
                SettingsPermissionKind.updateCachedLocationAuthorizationStatus(status)
                if monitor.currentSettings.useAutomaticAstronomyLocation,
                   granted {
                    monitor.refreshAstronomyCoordinatesFromSystem()
                }
            case .contacts:
                granted = await MeetingContactResolver.shared.requestAccess()
                contactsAuthorizationStatus = SettingsPermissionKind.currentContactsAuthorizationStatus(forceRefresh: true)
            }

            permissionActionMessages[permission] = granted
                ? "Access granted."
                : "macOS did not grant access. Use Open Settings to enable it for AlertCalendar."
            refreshPermissionStatuses()
        }
    }

    func refreshPermissionStatuses(forceRefresh: Bool = true) {
        eventAuthorizationStatus = SettingsPermissionKind.currentEventAuthorizationStatus(forceRefresh: forceRefresh)
        reminderAuthorizationStatus = SettingsPermissionKind.currentReminderAuthorizationStatus(forceRefresh: forceRefresh)
        locationAuthorizationStatus = SettingsPermissionKind.currentLocationAuthorizationStatus(forceRefresh: forceRefresh)
        contactsAuthorizationStatus = SettingsPermissionKind.currentContactsAuthorizationStatus(forceRefresh: forceRefresh)
        for permission in SettingsPermissionKind.allCases
            where permissionGrantState(for: permission) == .allowed
                && permissionActionMessages[permission] != "Access granted." {
            permissionActionMessages[permission] = nil
        }
        monitor.refreshAvailableCalendars()
        synchronizeSettingsStateFromMonitor()
        monitor.refreshNow(reason: .manual)
    }

    func openPrivacySettings() {
        let deepLinks = SettingsPermissionKind.allCases.map(\.privacySettingsDeepLink)

        for rawValue in deepLinks {
            guard let url = URL(string: rawValue) else { continue }
            if AlertCalendarWorkspace.open(url) {
                return
            }
        }

        if let settingsAppURL = URL(string: "x-apple.systempreferences:") {
            AlertCalendarWorkspace.open(settingsAppURL)
        }
    }

    func openPrivacySettings(for permission: SettingsPermissionKind) {
        guard let url = URL(string: permission.privacySettingsDeepLink) else {
            openPrivacySettings()
            return
        }

        if !AlertCalendarWorkspace.open(url) {
            openPrivacySettings()
        }
    }

    func statusPill(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(title):")
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    func stepperRow<Control: View>(title: String, valueText: String, helpText: String? = nil, @ViewBuilder control: () -> Control) -> some View {
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
}
