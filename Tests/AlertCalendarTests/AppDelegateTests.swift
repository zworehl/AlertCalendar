import AppKit
import SwiftUI
import XCTest
@testable import AlertCalendar

@MainActor
final class AppDelegateTests: XCTestCase {
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
        XCTAssertNil(zoomButton.target)
        XCTAssertNil(zoomButton.action)
    }

    func testShowSettingsWindowCreatesVisibleReusableWindow() throws {
        let appDelegate = AppDelegate()

        appDelegate.showSettingsWindow(rootView: AnyView(Text("First Settings")))

        let firstWindow = try XCTUnwrap(appDelegate.currentSettingsWindow)
        XCTAssertEqual(firstWindow.identifier, NSUserInterfaceItemIdentifier(WindowMetadata.preferencesID))
        XCTAssertEqual(firstWindow.title, WindowMetadata.preferencesTitle)
        XCTAssertGreaterThanOrEqual(firstWindow.frame.width, firstWindow.minSize.width)
        XCTAssertGreaterThanOrEqual(firstWindow.frame.height, firstWindow.minSize.height)
        XCTAssertTrue(firstWindow.isVisible)
        XCTAssertTrue(firstWindow.contentViewController is NSHostingController<AnyView>)

        appDelegate.showSettingsWindow(rootView: AnyView(Text("Updated Settings")))

        let secondWindow = try XCTUnwrap(appDelegate.currentSettingsWindow)
        XCTAssertTrue(firstWindow === secondWindow)
        XCTAssertTrue(secondWindow.isVisible)
    }

    func testRevealSettingsWindowIfPresentRestoresHiddenWindow() throws {
        let appDelegate = AppDelegate()

        appDelegate.showSettingsWindow(rootView: AnyView(Text("Settings")))

        let window = try XCTUnwrap(appDelegate.currentSettingsWindow)
        window.setFrame(NSRect(x: -5000, y: -5000, width: 240, height: 180), display: false)
        window.orderOut(nil)

        XCTAssertFalse(window.isVisible)

        XCTAssertTrue(appDelegate.revealSettingsWindowIfPresent())
        XCTAssertTrue(window.isVisible)
        XCTAssertGreaterThanOrEqual(window.frame.width, window.minSize.width)
        XCTAssertGreaterThanOrEqual(window.frame.height, window.minSize.height)
    }
}
