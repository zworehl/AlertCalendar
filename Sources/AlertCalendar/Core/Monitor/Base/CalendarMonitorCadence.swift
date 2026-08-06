import Foundation

enum CalendarMonitorCadence {
    static let heartbeatInterval: TimeInterval = 1
    static let menuBarAnimationInterval: TimeInterval = 1
    static let periodicRefreshInterval: TimeInterval = 15 * 60
    static let reminderFetchTimeoutInterval: TimeInterval = 12
    static let slackStatusHeartbeatInterval: TimeInterval = 60
    static let slackStatusSyncTaskTimeoutInterval: TimeInterval = 45
    static let slackDynamicStatusRotationInterval: TimeInterval = 30
    static let slackConnectionMetadataRefreshInterval: TimeInterval = 30 * 60
    static let slackDiagnosticsLogSizeLimit = 256 * 1024
}
