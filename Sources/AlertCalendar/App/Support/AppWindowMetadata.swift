import Foundation

enum WindowMetadata {
    static let preferencesID = "preferences"
    static var preferencesTitle: String { L10n.text("Settings") }
}

extension Notification.Name {
    static let alertCalendarReopenRequested = Notification.Name("AlertCalendar.reopenRequested")
}
