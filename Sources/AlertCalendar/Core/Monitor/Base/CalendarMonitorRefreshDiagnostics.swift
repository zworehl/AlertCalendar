import Foundation

enum CalendarMonitorRefreshReason: String, CaseIterable, Hashable {
    case launchSnapshot
    case launchConfirmation
    case launch
    case manual
    case settingsChanged
    case eventStoreChanged
    case workspaceResumed
    case periodic
    case footballHeartbeat
    case locationChanged
    case calendarSelectionChanged
    case focusFilterChanged
    case itemAction
    case footballCalendarAction
    case slackConnectionChanged
    case calendarSync
    case remindersChanged

    var title: String {
        switch self {
        case .launchSnapshot:
            return L10n.text("Initial calendar snapshot")
        case .launchConfirmation:
            return L10n.text("Initial calendar confirmation")
        case .launch:
            return L10n.text("Launch")
        case .manual:
            return L10n.text("Manual")
        case .settingsChanged:
            return L10n.text("Settings changed")
        case .eventStoreChanged:
            return L10n.text("Calendar changed")
        case .workspaceResumed:
            return L10n.text("Mac wake")
        case .periodic:
            return L10n.text("Periodic")
        case .footballHeartbeat:
            return L10n.text("Football update")
        case .locationChanged:
            return L10n.text("Location changed")
        case .calendarSelectionChanged:
            return L10n.text("Calendar selection changed")
        case .focusFilterChanged:
            return L10n.text("Focus filter changed")
        case .itemAction:
            return L10n.text("Item action")
        case .footballCalendarAction:
            return L10n.text("Football calendar action")
        case .slackConnectionChanged:
            return L10n.text("Slack connection changed")
        case .calendarSync:
            return L10n.text("Calendar sync")
        case .remindersChanged:
            return L10n.text("Reminders updated")
        }
    }

    var triggersManagedFootballSync: Bool {
        switch self {
        case .launch, .manual, .settingsChanged, .workspaceResumed, .periodic, .footballHeartbeat, .footballCalendarAction:
            return true
        case .launchSnapshot, .launchConfirmation, .eventStoreChanged, .locationChanged, .calendarSelectionChanged, .focusFilterChanged, .itemAction, .slackConnectionChanged, .calendarSync, .remindersChanged:
            return false
        }
    }

    var triggersFootballAutoAddSync: Bool {
        switch self {
        case .launch, .manual, .settingsChanged, .workspaceResumed, .periodic, .footballHeartbeat:
            return true
        case .launchSnapshot, .launchConfirmation, .eventStoreChanged, .locationChanged, .calendarSelectionChanged, .focusFilterChanged, .itemAction, .footballCalendarAction, .slackConnectionChanged, .calendarSync, .remindersChanged:
            return false
        }
    }

    var evaluatesGameSales: Bool {
        switch self {
        case .launch, .manual, .settingsChanged, .workspaceResumed, .periodic:
            return true
        case .launchSnapshot, .launchConfirmation, .eventStoreChanged, .footballHeartbeat, .locationChanged, .calendarSelectionChanged, .focusFilterChanged, .itemAction, .footballCalendarAction, .slackConnectionChanged, .calendarSync, .remindersChanged:
            return false
        }
    }

    var evaluatesGoogleHolidays: Bool {
        switch self {
        case .launch, .manual, .settingsChanged, .workspaceResumed, .periodic:
            return true
        case .launchSnapshot, .launchConfirmation, .eventStoreChanged, .footballHeartbeat, .locationChanged, .calendarSelectionChanged, .focusFilterChanged, .itemAction, .footballCalendarAction, .slackConnectionChanged, .calendarSync, .remindersChanged:
            return false
        }
    }

    var schedulesReminderFetch: Bool {
        self != .launchConfirmation && self != .remindersChanged && self != .footballHeartbeat
    }

    var forcesExternalFeedRefresh: Bool {
        self == .manual
    }

    var refreshesCalendarStateOnly: Bool {
        self == .launchSnapshot || self == .launchConfirmation || self == .focusFilterChanged || self == .calendarSync || self == .remindersChanged
    }

    var refreshesCalendarSnapshot: Bool {
        self != .footballHeartbeat
    }
}

struct CalendarMonitorRefreshPlan {
    let reasons: Set<CalendarMonitorRefreshReason>

    var primaryReason: CalendarMonitorRefreshReason {
        CalendarMonitorRefreshCoordinator.primaryReason(from: reasons)
    }

    var refreshesCalendarStateOnly: Bool {
        reasons.allSatisfy(\.refreshesCalendarStateOnly)
    }

    var refreshesCalendarSnapshot: Bool {
        reasons.contains(where: \.refreshesCalendarSnapshot)
    }

    var triggersManagedFootballSync: Bool {
        reasons.contains(where: \.triggersManagedFootballSync)
    }

    var triggersFootballAutoAddSync: Bool {
        reasons.contains(where: \.triggersFootballAutoAddSync)
    }

    var evaluatesGameSales: Bool {
        reasons.contains(where: \.evaluatesGameSales)
    }

    var evaluatesGoogleHolidays: Bool {
        reasons.contains(where: \.evaluatesGoogleHolidays)
    }

    var schedulesReminderFetch: Bool {
        reasons.contains(where: \.schedulesReminderFetch)
    }

    var forcesExternalFeedRefresh: Bool {
        reasons.contains(where: \.forcesExternalFeedRefresh)
    }

    var includesEventStoreChange: Bool {
        reasons.contains(.eventStoreChanged)
    }

    init(reasons: Set<CalendarMonitorRefreshReason>) {
        self.reasons = reasons.isEmpty ? [.manual] : reasons
    }
}

struct CalendarMonitorRefreshExecutionReport: Equatable {
    var phaseDurations: [String: TimeInterval] = [:]
}

struct CalendarMonitorRefreshDiagnostics: Equatable {
    var lastReason: CalendarMonitorRefreshReason?
    var lastStartedAt: Date?
    var lastFinishedAt: Date?
    var lastDuration: TimeInterval?
    var pendingReasons: Set<CalendarMonitorRefreshReason> = []
    var phaseDurations: [String: TimeInterval] = [:]

    var isInProgress: Bool {
        !pendingReasons.isEmpty || (lastStartedAt != nil && lastFinishedAt == nil)
    }

    var summary: String {
        guard let lastReason else { return L10n.text("Waiting for first refresh...") }
        let durationText = lastDuration.map { String(format: "%.2fs", $0) } ?? "running"
        return "\(lastReason.title) - \(durationText)"
    }

    var pendingSummary: String {
        guard !pendingReasons.isEmpty else { return L10n.text("None") }
        return pendingReasons
            .sorted { $0.title < $1.title }
            .map(\.title)
            .joined(separator: ", ")
    }

    var phasesSummary: String {
        guard !phaseDurations.isEmpty else { return L10n.text("None") }
        return phaseDurations
            .sorted { $0.key < $1.key }
            .map { "\($0.key) \(String(format: "%.2fs", $0.value))" }
            .joined(separator: ", ")
    }
}
