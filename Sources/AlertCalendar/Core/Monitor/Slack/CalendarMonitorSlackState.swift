import Foundation

struct CalendarMonitorSlackRuntimeState {
    var statusSyncTask: Task<Void, Never>?
    var statusSyncTaskStartedAt: Date?
    var statusSyncRunID: UUID?
    var statusSyncNeedsAnotherPass = false
    var queuedTargets: [CalendarMonitor.SlackStatusSyncTarget] = []
    var statusSyncTransitionTask: Task<Void, Never>?
    var scheduledTransitionDate: Date?
    var lastStatusSyncEvaluationDate: Date?
    var managedStateByConnectionID: [String: CalendarMonitor.SlackManagedStatusState] = [:]
    var lastDiagnosticsMessage: String?
    var lastDiagnosticsMessageDate: Date?
    var appleMusicTrackID: String?
    var appleMusicExpirationTimestamp: Int?
    var appleMusicElapsedDuration: TimeInterval?
    var appleMusicObservedAt: Date?
    var appleMusicLastPlayback: AppleMusicPlayback?
    var appleMusicLastSuccessfulObservationAt: Date?
}

extension CalendarMonitor {
    var slackStatusSyncTask: Task<Void, Never>? {
        get { slackRuntimeState.statusSyncTask }
        set { slackRuntimeState.statusSyncTask = newValue }
    }

    var slackStatusSyncTaskStartedAt: Date? {
        get { slackRuntimeState.statusSyncTaskStartedAt }
        set { slackRuntimeState.statusSyncTaskStartedAt = newValue }
    }

    var slackStatusSyncRunID: UUID? {
        get { slackRuntimeState.statusSyncRunID }
        set { slackRuntimeState.statusSyncRunID = newValue }
    }

    var slackStatusSyncNeedsAnotherPass: Bool {
        get { slackRuntimeState.statusSyncNeedsAnotherPass }
        set { slackRuntimeState.statusSyncNeedsAnotherPass = newValue }
    }

    var slackQueuedTargets: [CalendarMonitor.SlackStatusSyncTarget] {
        get { slackRuntimeState.queuedTargets }
        set { slackRuntimeState.queuedTargets = newValue }
    }

    var slackStatusSyncTransitionTask: Task<Void, Never>? {
        get { slackRuntimeState.statusSyncTransitionTask }
        set { slackRuntimeState.statusSyncTransitionTask = newValue }
    }

    var slackScheduledTransitionDate: Date? {
        get { slackRuntimeState.scheduledTransitionDate }
        set { slackRuntimeState.scheduledTransitionDate = newValue }
    }

    var lastSlackStatusSyncEvaluationDate: Date? {
        get { slackRuntimeState.lastStatusSyncEvaluationDate }
        set { slackRuntimeState.lastStatusSyncEvaluationDate = newValue }
    }

    var slackManagedStateByConnectionID: [String: CalendarMonitor.SlackManagedStatusState] {
        get { slackRuntimeState.managedStateByConnectionID }
        set { slackRuntimeState.managedStateByConnectionID = newValue }
    }

    var lastSlackDiagnosticsMessage: String? {
        get { slackRuntimeState.lastDiagnosticsMessage }
        set { slackRuntimeState.lastDiagnosticsMessage = newValue }
    }

    var lastSlackDiagnosticsMessageDate: Date? {
        get { slackRuntimeState.lastDiagnosticsMessageDate }
        set { slackRuntimeState.lastDiagnosticsMessageDate = newValue }
    }
}
