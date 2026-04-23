import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    func integrationDescription(for integration: SettingsIntegrationKind) -> String {
        switch integration {
        case .focusFilters:
            return focusFiltersIntegrationDescription()
        case .slackStatusSync:
            return slackIntegrationDescription()
        }
    }

    func focusFiltersIntegrationDescription() -> String {
        guard let activeFocusCalendarFilterState, activeFocusCalendarFilterState.hasActiveOverrides else {
            return "No active Focus override is changing calendars right now. AlertCalendar is using the default selection."
        }

        let eventSummary = focusSelectionSummary(
            for: activeFocusCalendarFilterState.selection(for: .event),
            calendars: availableEventCalendars,
            emptyFallback: "Events use the default selection"
        )
        let reminderSummary = focusSelectionSummary(
            for: activeFocusCalendarFilterState.selection(for: .reminder),
            calendars: availableReminderCalendars,
            emptyFallback: "Reminders use the default selection"
        )
        return "\(eventSummary). \(reminderSummary)."
    }

    func focusSelectionSummary(
        for selection: FocusCalendarSelectionOverride?,
        calendars: [AvailableCalendar],
        emptyFallback: String
    ) -> String {
        guard let selection, selection.isActive else { return emptyFallback }

        let names = calendars
            .filter { selection.calendarIDs.contains($0.id) }
            .map(\.title)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        guard !names.isEmpty else { return emptyFallback }

        let visibleNames: String
        if names.count > 2 {
            visibleNames = names.prefix(2).joined(separator: ", ") + " +\(names.count - 2) more"
        } else {
            visibleNames = names.joined(separator: ", ")
        }

        switch selection.action {
        case .hideSelected:
            return "Hide \(visibleNames)"
        case .showOnlySelected:
            return "Show only \(visibleNames)"
        }
    }

    func permissionPrimaryButton(
        for permission: SettingsPermissionKind,
        grantState: PermissionGrantState,
        isRequesting: Bool
    ) -> some View {
        Button {
            requestPermission(permission)
        } label: {
            Label(
                isRequesting ? "Checking..." : permissionPrimaryActionTitle(for: permission, state: grantState),
                systemImage: isRequesting ? "hourglass" : "arrow.clockwise.circle"
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
            Label("Open Settings", systemImage: "gearshape")
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
        Text(state.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(state.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(state.tint.opacity(0.12))
            )
    }

    func permissionPrimaryActionTitle(for permission: SettingsPermissionKind, state: PermissionGrantState) -> String {
        switch state {
        case .allowed:
            return "Check access"
        case .notRequested:
            return "Request access"
        case .limited:
            return permission == .location ? "Check access" : "Upgrade access"
        case .denied, .restricted:
            return "Check access"
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
                return astronomyLocationStatus
            case .notRequested:
                return "Location has not been requested yet. Grant it to support automatic astronomy coordinates and daylight maps, or enter coordinates manually below."
            case .limited:
                return astronomyLocationStatus
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
            let status = SettingsPermissionKind.currentLocationAuthorizationStatus()
            if status != locationAuthorizationStatus {
                locationAuthorizationStatus = status
            }
            return Self.permissionGrantState(for: status)
        case .contacts:
            let status = SettingsPermissionKind.currentContactsAuthorizationStatus()
            if status != contactsAuthorizationStatus {
                contactsAuthorizationStatus = status
            }
            return Self.permissionGrantState(for: status)
        }
    }

    func requestPermission(_ permission: SettingsPermissionKind) {
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
                if monitor.currentSettings.useAutomaticAstronomyLocation,
                   Self.permissionGrantState(for: status) == .allowed {
                    monitor.refreshAstronomyCoordinatesFromSystem()
                }
            case .contacts:
                _ = await MeetingContactResolver.shared.requestAccess()
                contactsAuthorizationStatus = SettingsPermissionKind.currentContactsAuthorizationStatus()
            }

            refreshPermissionStatuses()
        }
    }

    func refreshPermissionStatuses() {
        locationAuthorizationStatus = SettingsPermissionKind.currentLocationAuthorizationStatus()
        contactsAuthorizationStatus = SettingsPermissionKind.currentContactsAuthorizationStatus()
        monitor.refreshAvailableCalendars()
        synchronizeSettingsStateFromMonitor()
        monitor.refreshNow()
    }

    func openPrivacySettings() {
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

    func openPrivacySettings(for permission: SettingsPermissionKind) {
        guard let url = URL(string: permission.privacySettingsDeepLink) else {
            openPrivacySettings()
            return
        }

        if !NSWorkspace.shared.open(url) {
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
