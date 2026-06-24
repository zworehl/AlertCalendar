import Foundation

enum CalendarMonitorCadence {
    static let heartbeatInterval: TimeInterval = 1
    static let menuBarAnimationInterval: TimeInterval = 1.0 / 12.0
    static let periodicRefreshInterval: TimeInterval = 5 * 60
    static let reminderFetchTimeoutInterval: TimeInterval = 12
    static let slackStatusHeartbeatInterval: TimeInterval = 10
    static let slackConnectionMetadataRefreshInterval: TimeInterval = 30 * 60
    static let slackDiagnosticsLogSizeLimit = 256 * 1024
}
