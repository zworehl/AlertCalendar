import AppKit
import Foundation
import SwiftUI

extension MenuContentView {
    var displayReferenceDate: Date {
        dropdownReferenceDate
    }

    func prepareDropdownPresentation() {
        dropdownReferenceDate = AlertCalendarClock.nowRoundedToSecond()
        monitor.synchronizeCalendarStateIfNeeded()
        // Preference values can arrive before onAppear. Preserve them so this
        // presentation does not erase the split-column measurements SwiftUI just resolved.
    }

    func keepDropdownReferenceDateFresh() async {
        while !Task.isCancelled {
            let now = AlertCalendarClock.nowRoundedToSecond()
            let delay = monitor.nextPresentationRefreshInterval(now: now, settings: settings)
            do {
                try await Task.sleep(nanoseconds: CalendarMonitorTime.nanoseconds(forDelay: delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            dropdownReferenceDate = AlertCalendarClock.nowRoundedToSecond()
        }
    }
}

struct MenuWindowVisibilityObserver: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> MenuWindowVisibilityObserverView {
        let view = MenuWindowVisibilityObserverView()
        updateCallback(for: view)
        return view
    }

    func updateNSView(_ nsView: MenuWindowVisibilityObserverView, context: Context) {
        updateCallback(for: nsView)
        nsView.publishCurrentVisibility()
    }

    private func updateCallback(for view: MenuWindowVisibilityObserverView) {
        view.visibilityDidChange = { visible in
            Task { @MainActor in
                guard isVisible != visible else { return }
                isVisible = visible
            }
        }
    }
}

final class MenuWindowVisibilityObserverView: NSView {
    var visibilityDidChange: ((Bool) -> Void)?

    private weak var observedWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeWindow(window)
        DispatchQueue.main.async { [weak self] in
            self?.publishCurrentVisibility()
        }
    }

    func publishCurrentVisibility() {
        let visible = window?.isVisible ?? false
        visibilityDidChange?(visible)
    }

    private func observeWindow(_ window: NSWindow?) {
        guard observedWindow !== window else {
            publishCurrentVisibility()
            return
        }

        removeWindowObservers()
        observedWindow = window
        guard let window else {
            publishCurrentVisibility()
            return
        }

        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.willCloseNotification
        ]
        for name in names {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowVisibilityDidChange(_:)),
                name: name,
                object: window
            )
        }
        publishCurrentVisibility()
    }

    @objc private func windowVisibilityDidChange(_ notification: Notification) {
        if notification.name == NSWindow.willCloseNotification {
            visibilityDidChange?(false)
            return
        }
        publishCurrentVisibility()
    }

    private func removeWindowObservers() {
        NotificationCenter.default.removeObserver(self)
    }
}
