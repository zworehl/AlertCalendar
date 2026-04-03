import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsWindowIdentifier = NSUserInterfaceItemIdentifier(WindowMetadata.preferencesID)
    private let settingsDefaultSize = NSSize(width: 1040, height: 820)
    private var settingsWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ensureRegularActivationPolicy()
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
        if settingsWindowController?.window === window {
            settingsWindowController = nil
        }
    }

    private func isSettingsWindow(_ window: NSWindow) -> Bool {
        if window.identifier == settingsWindowIdentifier {
            return true
        }
        return window.title == WindowMetadata.preferencesTitle
    }

    func prepareForSettingsPresentation() {
        ensureRegularActivationPolicy()
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    @discardableResult
    func revealSettingsWindowIfPresent() -> Bool {
        guard let window = settingsWindowController?.window ?? NSApp.windows.first(where: isSettingsWindow) else {
            return false
        }

        presentSettingsWindow(window)
        return true
    }

    func showSettingsWindow(monitor: CalendarMonitor) {
        showSettingsWindow(rootView: AnyView(SettingsView(monitor: monitor)))
    }

    var currentSettingsWindow: NSWindow? {
        settingsWindowController?.window
    }

    func showSettingsWindow(rootView: AnyView) {
        if let window = settingsWindowController?.window {
            if let hostingController = window.contentViewController as? NSHostingController<AnyView> {
                hostingController.rootView = rootView
            } else {
                window.contentViewController = NSHostingController(rootView: rootView)
            }
            presentSettingsWindow(window)
            return
        }

        let window = makeSettingsWindow(rootView: rootView)

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        presentSettingsWindow(window)
    }

    private func ensureRegularActivationPolicy() {
        _ = NSApplication.shared.setActivationPolicy(.regular)
    }

    private func makeSettingsWindow(rootView: AnyView) -> NSWindow {
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: settingsDefaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = WindowMetadata.preferencesTitle
        window.isReleasedWhenClosed = false
        configureSettingsWindow(window)
        applySettingsWindowInitialFrame(window)
        return window
    }

    private func presentSettingsWindow(_ window: NSWindow) {
        prepareForSettingsPresentation()
        configureSettingsWindow(window)
        normalizeSettingsWindowFrameIfNeeded(window)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        settingsWindowController?.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    private func applySettingsWindowInitialFrame(_ window: NSWindow) {
        let restoredFrame = window.setFrameUsingName(WindowMetadata.preferencesID)
        guard !restoredFrame else {
            normalizeSettingsWindowFrameIfNeeded(window)
            return
        }

        centerSettingsWindow(window)
    }

    private func normalizeSettingsWindowFrameIfNeeded(_ window: NSWindow) {
        let minimumFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: window.minSize)).size
        let frame = window.frame
        let hasMinimumSize = frame.width >= minimumFrameSize.width && frame.height >= minimumFrameSize.height
        let isVisibleOnAnyScreen = NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(frame.insetBy(dx: -80, dy: -80))
        }

        guard hasMinimumSize && isVisibleOnAnyScreen else {
            centerSettingsWindow(window)
            return
        }
    }

    private func centerSettingsWindow(_ window: NSWindow) {
        let defaultFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: settingsDefaultSize)).size
        let visibleFrame = (window.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(origin: .zero, size: defaultFrameSize)
        let origin = NSPoint(
            x: visibleFrame.midX - defaultFrameSize.width / 2,
            y: visibleFrame.midY - defaultFrameSize.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: defaultFrameSize), display: false)
    }

    func configureSettingsWindow(_ window: NSWindow) {
        window.identifier = settingsWindowIdentifier
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
        window.collectionBehavior.remove(.fullScreenNone)
        window.collectionBehavior.insert([.fullScreenPrimary, .fullScreenAllowsTiling])
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 760, height: 720)
        window.setFrameAutosaveName(WindowMetadata.preferencesID)
        window.titleVisibility = .visible
        if let zoomButton = window.standardWindowButton(.zoomButton) {
            zoomButton.isHidden = false
            zoomButton.isEnabled = true
            zoomButton.target = nil
            zoomButton.action = nil
        }
        window.level = .normal
    }
}
