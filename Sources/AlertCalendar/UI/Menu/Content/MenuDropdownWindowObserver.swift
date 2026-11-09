import AppKit
import SwiftUI

struct MenuDropdownWindowObserver: NSViewRepresentable {
    @Binding var isVisible: Bool
    @Binding var availableSize: CGSize

    func makeNSView(context: Context) -> MenuDropdownWindowObserverView {
        let view = MenuDropdownWindowObserverView()
        updateCallbacks(view)
        return view
    }

    func updateNSView(_ nsView: MenuDropdownWindowObserverView, context: Context) {
        updateCallbacks(nsView)
        nsView.scheduleUpdate()
    }

    static func dismantleNSView(_ nsView: MenuDropdownWindowObserverView, coordinator: ()) {
        nsView.stopObserving()
    }

    private func updateCallbacks(_ view: MenuDropdownWindowObserverView) {
        view.presentationDidChange = { visible, currentSize in
            if isVisible != visible { isVisible = visible }
            if availableSize != currentSize { availableSize = currentSize }
        }
    }
}

/// Reports presentation and shared display constraints without changing panel
/// geometry. MenuBarController owns the panel's size, position, and focus.
final class MenuDropdownWindowObserverView: NSView {
    var presentationDidChange: ((Bool, CGSize) -> Void)?
    var connectedScreens: () -> [MenuDropdownScreen] = { MenuDropdownScreen.connected }

    private weak var observedWindow: NSWindow?
    private var visibilityObservation: NSKeyValueObservation?
    private var isUpdateScheduled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard observedWindow !== window else { return }
        stopObserving()
        observedWindow = window
        guard let window else {
            presentationDidChange?(false, MenuDropdownScreen.commonAvailableSize(screens: connectedScreens()))
            return
        }
        MenuDropdownAppearance.configure(window)

        let names: [Notification.Name] = [
            NSWindow.didChangeScreenNotification,
            NSWindow.didChangeBackingPropertiesNotification,
            NSWindow.willCloseNotification,
        ]
        for name in names {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidChange(_:)), name: name, object: window
            )
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        visibilityObservation = window.observe(\.isVisible, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.scheduleUpdate() }
        }
        scheduleUpdate()
    }

    func stopObserving() {
        visibilityObservation = nil
        NotificationCenter.default.removeObserver(self)
        observedWindow = nil
    }

    @objc private func windowDidChange(_ notification: Notification) {
        if let window = observedWindow,
           notification.name == NSWindow.didChangeBackingPropertiesNotification
                || notification.name == NSWindow.didChangeScreenNotification {
            MenuDropdownAppearance.configure(window)
        }
        scheduleUpdate()
    }

    func scheduleUpdate() {
        guard observedWindow != nil, !isUpdateScheduled else { return }
        isUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isUpdateScheduled = false
            self.updatePresentation()
        }
    }

    func updatePresentation() {
        guard let window = observedWindow else { return }
        presentationDidChange?(
            window.isVisible,
            MenuDropdownScreen.commonAvailableSize(screens: connectedScreens())
        )
    }

}
