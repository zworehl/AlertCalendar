import Foundation

enum CalendarMonitorRefreshReason: String, CaseIterable, Hashable {
    case launch
    case manual
    case settingsChanged
    case eventStoreChanged
    case periodic
    case footballHeartbeat
    case locationChanged
    case calendarSelectionChanged
    case itemAction
    case footballCalendarAction
    case slackConnectionChanged

    var title: String {
        switch self {
        case .launch:
            return "Launch"
        case .manual:
            return "Manual"
        case .settingsChanged:
            return "Settings changed"
        case .eventStoreChanged:
            return "Calendar changed"
        case .periodic:
            return "Periodic"
        case .footballHeartbeat:
            return "Football update"
        case .locationChanged:
            return "Location changed"
        case .calendarSelectionChanged:
            return "Calendar selection changed"
        case .itemAction:
            return "Item action"
        case .footballCalendarAction:
            return "Football calendar action"
        case .slackConnectionChanged:
            return "Slack connection changed"
        }
    }

    var triggersManagedFootballSync: Bool {
        switch self {
        case .launch, .manual, .settingsChanged, .eventStoreChanged, .periodic, .footballHeartbeat, .footballCalendarAction:
            return true
        case .locationChanged, .calendarSelectionChanged, .itemAction, .slackConnectionChanged:
            return false
        }
    }
}

struct CalendarMonitorRefreshDiagnostics: Equatable {
    var lastReason: CalendarMonitorRefreshReason?
    var lastStartedAt: Date?
    var lastFinishedAt: Date?
    var lastDuration: TimeInterval?
    var pendingReasons: Set<CalendarMonitorRefreshReason> = []

    var summary: String {
        guard let lastReason else { return "Waiting for first refresh..." }
        let durationText = lastDuration.map { String(format: "%.2fs", $0) } ?? "running"
        return "\(lastReason.title) - \(durationText)"
    }

    var pendingSummary: String {
        guard !pendingReasons.isEmpty else { return "None" }
        return pendingReasons
            .sorted { $0.title < $1.title }
            .map(\.title)
            .joined(separator: ", ")
    }
}
