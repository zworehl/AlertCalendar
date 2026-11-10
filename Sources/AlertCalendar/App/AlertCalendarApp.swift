import AppKit
import SwiftUI

/// AppKit owns window presentation; SwiftUI owns the content of those windows.
@MainActor
final class AlertCalendarApp {
    private let monitor = CalendarMonitor()
    private weak var appDelegate: AppDelegate?
    private var menuBar: MenuBarController?
    private var settingsWindow: NSWindow?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func start() {
        guard menuBar == nil else { return }
        let menuBar = MenuBarController(presentation: monitor.menuBarPresentationModel)
        self.menuBar = menuBar
        let actions = MenuDropdownActions(
            dismiss: { [weak menuBar] in menuBar?.dismiss() },
            openSettings: { [weak self] in self?.showSettings() }
        )
        menuBar.setContent(AnyView(
            LocalizedAppContent { [monitor] in
                MenuContentView(kindFilter: nil, headerTitle: "Alert Calendar")
                    .environmentObject(monitor)
                    .environment(\.menuDropdownActions, actions)
            }
        ))
    }

    func showSettings() {
        menuBar?.dismiss()
        appDelegate?.prepareForSettingsPresentation()
        let window: NSWindow
        if let existing = settingsWindow {
            window = existing
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1240, height: 840),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.identifier = NSUserInterfaceItemIdentifier(WindowMetadata.preferencesID)
            window.title = WindowMetadata.preferencesTitle
            window.toolbarStyle = .unified
            appDelegate?.configureSettingsWindow(window)
            if !window.setFrameUsingName(WindowMetadata.preferencesID) { window.center() }
            window.contentView = NSHostingView(rootView: LocalizedAppContent { [monitor] in
                SettingsView(monitor: monitor)
            })
            settingsWindow = window
        }
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
    }

    func stop() {
        menuBar?.stop()
        menuBar = nil
    }

    func prepareForTermination() async {
        await monitor.flushPersistentCachesForTermination()
    }

    func settingsDidClose(_ window: NSWindow) {
        guard window === settingsWindow else { return }
        // Recreate the view on the next opening so its draft and close guard
        // start together, including their apply/discard callbacks.
        settingsWindow = nil
        window.contentView = nil
    }
}

private struct LocalizedAppContent<Content: View>: View {
    @AppStorage(DefaultsKeys.language) private var language = AppLanguage.english.rawValue
    @ViewBuilder var content: () -> Content

    var body: some View {
        content().environment(\.locale, (AppLanguage(rawValue: language) ?? .english).locale)
    }
}
