import Foundation

enum WindowMetadata {
    static let preferencesID = "preferences"
    static let preferencesTitle = "Settings"
}

extension Notification.Name {
    static let alertCalendarOpenSettingsRequested = Notification.Name(
        "AlertCalendar.openSettingsRequested"
    )
}
