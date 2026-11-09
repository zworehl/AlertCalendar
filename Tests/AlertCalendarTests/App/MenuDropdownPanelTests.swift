import AppKit
import XCTest
@testable import AlertCalendar

@MainActor
final class MenuDropdownPanelTests: XCTestCase {
    func testPanelAcceptsKeyboardWithoutActivatingTheApplicationOrItsMainWindow() {
        let panel = MenuDropdownPanel()
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(panel.autorecalculatesKeyViewLoop)
        XCTAssertEqual(panel.animationBehavior, .none)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    func testEscapeRoutesThroughOwnerInsteadOfClosingTheWindowIndependently() {
        let panel = MenuDropdownPanel()
        var dismissals = 0
        panel.onDismiss = { dismissals += 1 }
        panel.cancelOperation(nil)
        XCTAssertEqual(dismissals, 1)
    }

    func testStatusButtonAndContentRemainInsideDuringTheClosingMouseDown() {
        let panel = makePanel()
        let button = NSRect(x: 600, y: 500, width: 100, height: 24)
        for point in [NSPoint(x: 620, y: 510), NSPoint(x: 620, y: 200)] {
            XCTAssertTrue(MenuDropdownHitTesting.isInsidePresentation(
                point: point, eventWindow: nil, panel: panel, buttonFrame: button
            ))
        }
        XCTAssertFalse(MenuDropdownHitTesting.isInsidePresentation(
            point: NSPoint(x: 50, y: 50), eventWindow: nil, panel: panel, buttonFrame: button
        ))
    }

    func testAnotherWindowOfTheSameApplicationIsAnOutsideClick() {
        let panel = makePanel()
        let settings = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        settings.identifier = NSUserInterfaceItemIdentifier(WindowMetadata.preferencesID)
        XCTAssertFalse(MenuDropdownHitTesting.isInsidePresentation(
            point: NSPoint(x: 50, y: 50), eventWindow: settings, panel: panel, buttonFrame: nil
        ))
    }

    func testChildPopoverAndNativeMenuCanReceiveActionsWithoutPrematureDismissal() {
        let panel = makePanel()
        let child = NSPanel(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        child.parent = panel
        defer { child.parent = nil }
        let menuWindow = NSPanel(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        menuWindow.level = .popUpMenu
        for window in [child, menuWindow] {
            XCTAssertTrue(MenuDropdownHitTesting.isInsidePresentation(
                point: NSPoint(x: 50, y: 50), eventWindow: window, panel: panel, buttonFrame: nil
            ))
        }
    }

    private func makePanel() -> MenuDropdownPanel {
        let panel = MenuDropdownPanel()
        panel.setFrame(NSRect(x: 400, y: 100, width: 300, height: 396), display: false)
        return panel
    }
}
