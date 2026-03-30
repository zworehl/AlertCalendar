import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsWindowIdentifier = NSUserInterfaceItemIdentifier(WindowMetadata.preferencesID)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setDockIconVisible(false)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func handleWindowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard isSettingsWindow(window) else { return }
        prepareForSettingsPresentation()
        configureSettingsWindow(window)
    }

    @objc
    private func handleWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard isSettingsWindow(window) else { return }

        let hasAnotherVisibleSettingsWindow = NSApp.windows.contains { candidate in
            candidate !== window && candidate.isVisible && isSettingsWindow(candidate)
        }
        if !hasAnotherVisibleSettingsWindow {
            setDockIconVisible(false)
        }
    }

    private func isSettingsWindow(_ window: NSWindow) -> Bool {
        if window.identifier == settingsWindowIdentifier {
            return true
        }
        return window.title == WindowMetadata.preferencesTitle
    }

    func prepareForSettingsPresentation() {
        setDockIconVisible(true)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func setDockIconVisible(_ visible: Bool) {
        let policy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        _ = NSApplication.shared.setActivationPolicy(policy)
    }

    func configureSettingsWindow(_ window: NSWindow) {
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
        window.collectionBehavior.insert([.fullScreenPrimary, .fullScreenAllowsTiling])
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 760, height: 720)
        window.titleVisibility = .visible
        window.standardWindowButton(.zoomButton)?.isHidden = false
        window.level = .normal
    }
}
