import AppKit
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

        appDelegate.configureSettingsWindow(window)

        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAllowsTiling))

        let zoomButton = try XCTUnwrap(window.standardWindowButton(.zoomButton))
        XCTAssertFalse(zoomButton.isHidden)
        XCTAssertTrue(zoomButton.target === window)
        XCTAssertEqual(zoomButton.action, #selector(NSWindow.toggleFullScreen(_:)))
    }
}
