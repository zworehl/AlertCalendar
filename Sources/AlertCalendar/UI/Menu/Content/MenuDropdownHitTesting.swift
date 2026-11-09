import AppKit

enum MenuDropdownHitTesting {
    @MainActor
    static func isInsidePresentation(
        point: NSPoint, eventWindow: NSWindow?, panel: NSWindow, buttonFrame: NSRect?
    ) -> Bool {
        if panel.frame.contains(point) || buttonFrame?.contains(point) == true { return true }
        var ancestor = eventWindow
        while let window = ancestor {
            if window === panel { return true }
            ancestor = window.parent
        }
        // Native menus may use an independent tracking window. Normal app
        // windows, including Settings, must still count as outside clicks.
        return eventWindow.map { $0.level >= .popUpMenu } ?? false
    }
}
