import AppKit
import XCTest
@testable import AlertCalendar

@MainActor
final class AppDelegateTests: XCTestCase {
    func testPrepareForSettingsPresentationMakesAppRegularForSettings() {
        let appDelegate = AppDelegate()
        let application = NSApplication.shared
        let originalPolicy = application.activationPolicy()
        defer { _ = application.setActivationPolicy(originalPolicy) }

        _ = application.setActivationPolicy(.accessory)

        appDelegate.prepareForSettingsPresentation()

        XCTAssertEqual(application.activationPolicy(), .regular)
    }

    func testRestoreAccessoryActivationPolicyReturnsAppToMenuBarMode() {
        let appDelegate = AppDelegate()
        let application = NSApplication.shared
        let originalPolicy = application.activationPolicy()
        defer { _ = application.setActivationPolicy(originalPolicy) }

        _ = application.setActivationPolicy(.regular)

        appDelegate.restoreAccessoryActivationPolicyIfNeeded()

        XCTAssertEqual(application.activationPolicy(), .accessory)
    }

    func testConfigureSettingsWindowEnablesFullScreenZoomButton() throws {
        let appDelegate = AppDelegate()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.collectionBehavior.insert(.fullScreenNone)
        appDelegate.configureSettingsWindow(window)

        XCTAssertEqual(window.identifier, NSUserInterfaceItemIdentifier(WindowMetadata.preferencesID))
        XCTAssertFalse(window.collectionBehavior.contains(.fullScreenNone))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAllowsTiling))
        XCTAssertEqual(window.frameAutosaveName, WindowMetadata.preferencesID)
        let zoomButton = try XCTUnwrap(window.standardWindowButton(.zoomButton))
        XCTAssertFalse(zoomButton.isHidden)
        XCTAssertTrue(zoomButton.isEnabled)
        XCTAssertEqual(zoomButton.action, #selector(AppDelegate.toggleSettingsFullScreen(_:)))
        XCTAssertTrue((zoomButton.target as AnyObject?) === appDelegate)

    }

    func testApplyingPendingSettingsRunsApplyClosureAndAllowsExit() {
        let appDelegate = AppDelegate()
        let closeGuard = SettingsWindowCloseGuard()
        let window = settingsWindow()
        var applyCount = 0

        closeGuard.hasUnsavedChanges = true
        closeGuard.applyChanges = {
            applyCount += 1
        }
        appDelegate.configureSettingsWindow(window, closeGuard: closeGuard)

        XCTAssertTrue(appDelegate.resolveUnsavedSettingsChanges(.apply))
        XCTAssertEqual(applyCount, 1)
        XCTAssertFalse(closeGuard.hasUnsavedChanges)
    }

    func testDiscardingPendingSettingsRunsDiscardClosureAndAllowsExit() {
        let appDelegate = AppDelegate()
        let closeGuard = SettingsWindowCloseGuard()
        let window = settingsWindow()
        var discardCount = 0

        closeGuard.hasUnsavedChanges = true
        closeGuard.discardChanges = {
            discardCount += 1
        }
        appDelegate.configureSettingsWindow(window, closeGuard: closeGuard)

        XCTAssertTrue(appDelegate.resolveUnsavedSettingsChanges(.discard))
        XCTAssertEqual(discardCount, 1)
        XCTAssertFalse(closeGuard.hasUnsavedChanges)
    }

    func testKeepingPendingSettingsOpenPreservesDirtyState() {
        let appDelegate = AppDelegate()
        let closeGuard = SettingsWindowCloseGuard()
        let window = settingsWindow()

        closeGuard.hasUnsavedChanges = true
        appDelegate.configureSettingsWindow(window, closeGuard: closeGuard)

        XCTAssertFalse(appDelegate.resolveUnsavedSettingsChanges(.keepEditing))
        XCTAssertTrue(closeGuard.hasUnsavedChanges)
    }

    func testMissingPendingSettingsCallbackPreventsDataLoss() {
        let appDelegate = AppDelegate()
        let closeGuard = SettingsWindowCloseGuard()
        let window = settingsWindow()

        closeGuard.hasUnsavedChanges = true
        appDelegate.configureSettingsWindow(window, closeGuard: closeGuard)

        XCTAssertFalse(appDelegate.resolveUnsavedSettingsChanges(.apply))
        XCTAssertFalse(appDelegate.resolveUnsavedSettingsChanges(.discard))
        XCTAssertTrue(closeGuard.hasUnsavedChanges)
    }

    private func settingsWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }
}
