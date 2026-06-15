import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settingsWindowIdentifier = NSUserInterfaceItemIdentifier(WindowMetadata.preferencesID)
    private var emojiShortcutMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NSApp.mainMenu = makeMainMenu()
        installEmojiShortcutMonitor()
        ensureAccessoryActivationPolicy()
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

    func applicationWillTerminate(_ notification: Notification) {
        if let emojiShortcutMonitor {
            NSEvent.removeMonitor(emojiShortcutMonitor)
            self.emojiShortcutMonitor = nil
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func installEmojiShortcutMonitor() {
        emojiShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.shouldOpenEmojiPalette(for: event) else { return event }
            NSApp.orderFrontCharacterPalette(nil)
            return nil
        }
    }

    private func shouldOpenEmojiPalette(for event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.function) else { return false }
        guard event.charactersIgnoringModifiers?.lowercased() == "e" else { return false }
        return NSApp.keyWindow?.firstResponder is NSTextView
    }

    @objc
    private func handleWindowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard isSettingsWindow(window) else { return }
        prepareForSettingsPresentation()
        configureSettingsWindow(window)
        window.makeMain()
    }

    @objc
    private func handleWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard isSettingsWindow(window) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.restoreAccessoryActivationPolicyIfNeeded()
        }
    }

    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        proposedOptions.union([.autoHideDock, .autoHideMenuBar])
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

    @objc
    func toggleSettingsFullScreen(_ sender: Any?) {
        guard let window = resolvedSettingsWindow(sender: sender) else { return }

        prepareForSettingsPresentation()
        configureSettingsWindow(window)
        window.makeKeyAndOrderFront(nil)
        window.makeMain()

        DispatchQueue.main.async {
            window.toggleFullScreen(nil)
        }
    }

    func restoreAccessoryActivationPolicyIfNeeded() {
        guard !hasVisibleSettingsWindow else { return }
        ensureAccessoryActivationPolicy()
    }

    private func ensureAccessoryActivationPolicy() {
        _ = NSApplication.shared.setActivationPolicy(.accessory)
    }

    private func ensureRegularActivationPolicy() {
        _ = NSApplication.shared.setActivationPolicy(.regular)
    }

    private var hasVisibleSettingsWindow: Bool {
        return NSApp.windows.contains { window in
            isSettingsWindow(window) && window.isVisible
        }
    }

    private func resolvedSettingsWindow(sender: Any?) -> NSWindow? {
        if let control = sender as? NSControl, let senderWindow = control.window, isSettingsWindow(senderWindow) {
            return senderWindow
        }

        if let window = sender as? NSWindow, isSettingsWindow(window) {
            return window
        }

        return [NSApp.keyWindow, NSApp.mainWindow]
            .compactMap { $0 }
            .first(where: isSettingsWindow)
            ?? NSApp.windows.first(where: isSettingsWindow)
    }

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(ProcessInfo.processInfo.processName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide \(ProcessInfo.processInfo.processName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit \(ProcessInfo.processInfo.processName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())

        let emojiItem = NSMenuItem(
            title: "Emoji & Symbols",
            action: #selector(NSApplication.orderFrontCharacterPalette(_:)),
            keyEquivalent: "e"
        )
        emojiItem.keyEquivalentModifierMask = [.function]
        emojiItem.target = NSApp
        editMenu.addItem(emojiItem)
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let toggleFullScreenItem = NSMenuItem(title: "Toggle Full Screen", action: #selector(toggleSettingsFullScreen(_:)), keyEquivalent: "f")
        toggleFullScreenItem.keyEquivalentModifierMask = [.control, .command]
        toggleFullScreenItem.target = self
        viewMenu.addItem(toggleFullScreenItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        return mainMenu
    }

    func configureSettingsWindow(_ window: NSWindow) {
        window.identifier = settingsWindowIdentifier
        window.delegate = self
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
            zoomButton.target = self
            zoomButton.action = #selector(toggleSettingsFullScreen(_:))
        }
        window.level = .normal
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
