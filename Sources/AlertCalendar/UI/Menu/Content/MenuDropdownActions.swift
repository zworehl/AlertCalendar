import SwiftUI

/// Route dismissals through the presentation owner instead of hiding an
/// arbitrary key window and leaving its native status-item session active.
struct MenuDropdownActions {
    var dismiss: @MainActor () -> Void = {}
    var openSettings: @MainActor () -> Void = {}
}

private struct MenuDropdownActionsKey: EnvironmentKey {
    static let defaultValue = MenuDropdownActions()
}

extension EnvironmentValues {
    var menuDropdownActions: MenuDropdownActions {
        get { self[MenuDropdownActionsKey.self] }
        set { self[MenuDropdownActionsKey.self] = newValue }
    }
}
