import AppKit
import Combine
import SwiftUI
import os

/// Owns one status item and one panel. The button performs one toggle;
/// outside-click monitoring never dismisses a click on that same button.
@MainActor
final class MenuBarController: NSObject, NSWindowDelegate {
    private let statusItem: NSStatusItem
    private let panel = MenuDropdownPanel()
    private let label: MenuBarStatusItemLabelRenderer?
    private var buttonAction: MenuBarButtonAction?
    private var hostingView: MenuDropdownHostingView?
    private var monitors: [Any] = []
    private var observations = Set<AnyCancellable>()
    private var isStopped = false
    private var isResizeScheduled = false
    private static let logger = Logger(subsystem: "com.zworehl.alertcalendar", category: "menu-dropdown")

    init(presentation: MenuBarPresentationModel, persistsPosition: Bool = true) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if persistsPosition { statusItem.autosaveName = "AlertCalendar.status" }
        label = statusItem.button.map {
            MenuBarStatusItemLabelRenderer(presentation: presentation, button: $0)
        }
        super.init()
        panel.delegate = self
        panel.onDismiss = { [weak self] in self?.dismiss() }
        buttonAction = statusItem.button.map {
            MenuBarButtonAction(button: $0) { [weak self] in self?.toggleFromStatusButton() }
        }
        observeDismissalEvents()
        Self.logger.notice("Menu controller started button-action presentation")
    }

    func setContent(_ content: AnyView) {
        let view = MenuDropdownHostingView(rootView: content)
        view.sizingOptions = [.intrinsicContentSize]
        view.onSizeChange = { [weak self] in self?.scheduleResize() }
        hostingView = view
        panel.contentView = view
    }

    func dismiss() {
        guard !isStopped else { return }
        endPresentation()
    }

    var isPresented: Bool { panel.isVisible }

    func present() {
        beginPresentation()
    }

    func stop() {
        guard !isStopped else { return }
        dismiss()
        isStopped = true
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observations.removeAll()
        label?.stop()
        buttonAction?.stop()
        buttonAction = nil
        panel.orderOut(nil)
        panel.delegate = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func toggleFromStatusButton() {
        guard !isStopped else { return }
        let eventType = NSApp.currentEvent?.type.rawValue ?? 0
        Self.logger.notice("button action event-type=\(eventType, privacy: .public) visible=\(self.panel.isVisible, privacy: .public) app-active=\(NSApp.isActive, privacy: .public)")
        if panel.isVisible { endPresentation() }
        else { beginPresentation() }
    }

    private func beginPresentation() {
        guard !isStopped, !panel.isVisible, hostingView != nil else { return }
        guard resizeAndPosition() else {
            Self.logger.error("Unable to measure or anchor dropdown")
            dismiss()
            return
        }
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
        Self.logger.notice("panel opened app-active=\(NSApp.isActive, privacy: .public) key=\(self.panel.isKeyWindow, privacy: .public)")
    }

    private func endPresentation() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        Self.logger.notice("panel closed app-active=\(NSApp.isActive, privacy: .public) key=\(self.panel.isKeyWindow, privacy: .public)")
    }

    private var buttonFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    @discardableResult
    private func resizeAndPosition() -> Bool {
        guard let hostingView, let buttonFrame else { return false }
        let screens = MenuDropdownScreen.connected
        guard let visibleFrame = MenuDropdownScreen.visibleFrameForDropdown(
            windowFrame: buttonFrame, screens: screens
        ) else { return false }
        let size = hostingView.fittingSize
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return false }
        let frame = MenuDropdownPlacement.frame(contentSize: size, buttonFrame: buttonFrame,
                                                visibleFrame: visibleFrame)
        if panel.frame != frame { panel.setFrame(frame, display: panel.isVisible) }
        return true
    }

    private func scheduleResize() {
        guard !isResizeScheduled, !isStopped else { return }
        isResizeScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isResizeScheduled = false
            if self.panel.isVisible { self.resizeAndPosition() }
        }
    }

    private func observeDismissalEvents() {
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents, handler: { [weak self] event in
            self?.dismissForOutsideClick(at: NSEvent.mouseLocation, eventWindow: event.window)
            return event
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents, handler: { [weak self] _ in
            self?.dismissForOutsideClick(at: NSEvent.mouseLocation, eventWindow: nil)
        }) { monitors.append(monitor) }
        AlertCalendarWorkspace.notificationPublisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.dismiss() }
            .store(in: &observations)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.dismiss() }
            .store(in: &observations)
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: panel)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.panel.isVisible else { return }
                // Clicking the item must be handled once, by its own action.
                if self.buttonFrame?.contains(NSEvent.mouseLocation) == true { return }
                if let key = NSApp.keyWindow, key.parent === self.panel { return }
                Self.logger.notice("dismissal reason=resigned-key")
                self.dismiss()
            }.store(in: &observations)
    }

    private func dismissForOutsideClick(at point: NSPoint, eventWindow: NSWindow?) {
        guard panel.isVisible else { return }
        if MenuDropdownHitTesting.isInsidePresentation(
            point: point, eventWindow: eventWindow, panel: panel, buttonFrame: buttonFrame
        ) { return }
        Self.logger.notice("dismissal reason=outside-click")
        dismiss()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        Self.logger.notice("panel became key app-active=\(NSApp.isActive, privacy: .public)")
    }

    func windowDidResignKey(_ notification: Notification) {
        Self.logger.notice("panel resigned key app-active=\(NSApp.isActive, privacy: .public)")
    }
}
