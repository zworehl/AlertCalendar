import Foundation

extension CalendarMonitor {
    struct MenuBarRotationState: Equatable {
        var slot: Int?
        var selectedKey: String?
        var selectedIndex: Int?
        var startedAt: Date?
    }
}
