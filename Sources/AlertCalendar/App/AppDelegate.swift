import AppKit
import UserNotifications

enum SettingsUnsavedChangesChoice {
    case apply
    case discard
    case keepEditing
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settingsWindowIdentifier = NSUserInterfaceItemIdentifier(WindowMetadata.preferencesID)
    private var emojiShortcutMonitor: Any?
    private weak var settingsWindowCloseGuard: SettingsWindowCloseGuard?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SoftwareUpdateController.shared.start()
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard settingsWindowCloseGuard?.hasUnsavedChanges == true else {
            return .terminateNow
        }

        let choice = presentUnsavedSettingsAlert()
        return resolveUnsavedSettingsChanges(choice) ? .terminateNow : .terminateCancel
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
        settingsWindowCloseGuard?.clear()
        settingsWindowCloseGuard = nil
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

    @objc
    func openSettingsFromMainMenu(_ sender: Any?) {
        if let window = resolvedSettingsWindow(sender: sender) {
            prepareForSettingsPresentation()
            configureSettingsWindow(window)
            window.makeKeyAndOrderFront(nil)
            window.makeMain()
            return
        }

        NotificationCenter.default.post(name: .alertCalendarOpenSettingsRequested, object: nil)
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
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsFromMainMenu(_:)),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())
        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SoftwareUpdateController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = SoftwareUpdateController.shared
        appMenu.addItem(checkForUpdatesItem)
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

    func configureSettingsWindow(_ window: NSWindow, closeGuard: SettingsWindowCloseGuard? = nil) {
        if let closeGuard {
            settingsWindowCloseGuard = closeGuard
        }
        window.identifier = settingsWindowIdentifier
        window.delegate = self
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
        window.collectionBehavior.remove(.fullScreenNone)
        window.collectionBehavior.insert([.fullScreenPrimary, .fullScreenAllowsTiling])
        window.tabbingMode = .disallowed
        let minimumSettingsSize = NSSize(width: 980, height: 720)
        window.minSize = minimumSettingsSize
        if window.frame.width < minimumSettingsSize.width || window.frame.height < minimumSettingsSize.height {
            window.setContentSize(
                NSSize(
                    width: max(window.frame.width, minimumSettingsSize.width),
                    height: max(window.frame.height, minimumSettingsSize.height)
                )
            )
        }
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

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isSettingsWindow(sender),
              let closeGuard = settingsWindowCloseGuard,
              closeGuard.hasUnsavedChanges else {
            return true
        }

        return resolveUnsavedSettingsChanges(presentUnsavedSettingsAlert())
    }

    func resolveUnsavedSettingsChanges(_ choice: SettingsUnsavedChangesChoice) -> Bool {
        guard let closeGuard = settingsWindowCloseGuard,
              closeGuard.hasUnsavedChanges else {
            return true
        }

        switch choice {
        case .apply:
            guard let applyChanges = closeGuard.applyChanges else { return false }
            applyChanges()
            closeGuard.hasUnsavedChanges = false
            return true
        case .discard:
            guard let discardChanges = closeGuard.discardChanges else { return false }
            discardChanges()
            closeGuard.hasUnsavedChanges = false
            return true
        case .keepEditing:
            return false
        }
    }

    private func presentUnsavedSettingsAlert() -> SettingsUnsavedChangesChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Apply changes before leaving Settings?"
        alert.informativeText = "Configuration changes are staged until you apply them. You can apply them now, discard them, or keep editing."
        alert.addButton(withTitle: "Apply Changes")
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Keep Editing")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .apply
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .keepEditing
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier == CalendarMonitor.dataRefreshNotificationID,
           response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Task { @MainActor [weak self] in
                UserDefaults.standard.set(SettingsView.SettingsTab.access.rawValue, forKey: SettingsNavigationPersistence.selectedTabKey)
                self?.openSettingsFromMainMenu(nil)
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
