import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

@MainActor
final class SettingsWindowCloseGuard: ObservableObject {
    var hasUnsavedChanges = false
    var applyChanges: (() -> Void)?
    var discardChanges: (() -> Void)?

    func clear() {
        hasUnsavedChanges = false
        applyChanges = nil
        discardChanges = nil
    }
}

extension SettingsView {
    func configureSettingsWindowCloseGuard() {
        settingsWindowCloseGuard.hasUnsavedChanges = hasUnsavedChanges
        settingsWindowCloseGuard.applyChanges = {
            applyDraft()
        }
        settingsWindowCloseGuard.discardChanges = {
            resetDraft()
        }
    }

    func activateSettingsWindowIfNeeded() {
        guard let window = resolvedSettingsWindow() else { return }
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.prepareForSettingsPresentation()
            appDelegate.configureSettingsWindow(window, closeGuard: settingsWindowCloseGuard)
        } else {
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
        window.makeKeyAndOrderFront(nil)
    }

    func resolvedSettingsWindow() -> NSWindow? {
        let settingsIdentifier = NSUserInterfaceItemIdentifier(WindowMetadata.preferencesID)
        let matchesSettingsWindow: (NSWindow) -> Bool = { window in
            window.identifier == settingsIdentifier || window.title == WindowMetadata.preferencesTitle
        }

        return [NSApp.keyWindow, NSApp.mainWindow]
            .compactMap { $0 }
            .first(where: matchesSettingsWindow)
            ?? NSApp.windows.first(where: { window in
                matchesSettingsWindow(window) && window.isVisible
            })
            ?? NSApp.windows.first(where: matchesSettingsWindow)
    }

}
