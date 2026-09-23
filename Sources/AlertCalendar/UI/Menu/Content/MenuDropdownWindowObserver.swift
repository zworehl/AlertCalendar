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

/// Observe presentation and display constraints. AppKit owns horizontal
/// status-item anchoring; this view only repairs large vertical drift caused
/// when MenuBarExtra shrinks from its initial maximum content height.
final class MenuDropdownWindowObserverView: NSView {
    var presentationDidChange: ((Bool, CGSize) -> Void)?
    var connectedScreens: () -> [MenuDropdownScreen] = { MenuDropdownScreen.connected }

    private weak var observedWindow: NSWindow?
    private var visibilityObservation: NSKeyValueObservation?
    private var isUpdateScheduled = false
    private var stabilizationGeneration = 0

    private static let stabilizationDelays: [TimeInterval] = [0.05, 0.15, 0.35]

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard observedWindow !== window else { return }
        stopObserving()
        observedWindow = window
        guard let window else { return }
        MenuDropdownAppearance.configure(window)

        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
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
        stabilizationGeneration += 1
        visibilityObservation = nil
        NotificationCenter.default.removeObserver(self)
        observedWindow = nil
    }

    @objc private func windowDidChange(_ notification: Notification) {
        if let window = observedWindow,
           notification.name == NSWindow.didBecomeKeyNotification
                || notification.name == NSWindow.didResizeNotification
                || notification.name == NSWindow.didChangeBackingPropertiesNotification
                || notification.name == NSWindow.didChangeScreenNotification
                || notification.name == NSApplication.didChangeScreenParametersNotification {
            MenuDropdownAppearance.configure(window)
        }
        scheduleUpdate()
    }

    func scheduleUpdate() {
        guard !isUpdateScheduled else { return }
        isUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isUpdateScheduled = false
            self.updatePresentation()
            self.scheduleStabilizationPasses()
        }
    }

    private func scheduleStabilizationPasses() {
        stabilizationGeneration += 1
        let generation = stabilizationGeneration

        for delay in Self.stabilizationDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.stabilizationGeneration == generation else { return }
                self.updatePresentation()
            }
        }
    }

    func updatePresentation() {
        guard let window = observedWindow else { return }
        correctLargeVerticalGapIfNeeded(window)
        presentationDidChange?(
            window.isVisible,
            MenuDropdownScreen.commonAvailableSize(screens: connectedScreens())
        )
    }

    private func correctLargeVerticalGapIfNeeded(_ window: NSWindow) {
        guard window.isVisible else { return }
        let screens = connectedScreens()
        guard let visibleFrame = MenuDropdownScreen.visibleFrameForDropdown(
            windowFrame: window.frame,
            screens: screens
        ) ?? window.screen?.visibleFrame else { return }
        guard let origin = MenuDropdownScreen.correctedDropdownOrigin(
            windowFrame: window.frame,
            visibleFrame: visibleFrame
        ) else { return }
        window.setFrameTopLeftPoint(
            CGPoint(x: origin.x, y: origin.y + window.frame.height)
        )
    }
}
