import AppKit
import XCTest
@testable import AlertCalendar

@MainActor
final class MenuBarButtonActionTests: XCTestCase {
    func testStatusButtonSendsOnlyOneMouseDownActionWithoutContinuousTracking() {
        let button = makeButton()
        button.isContinuous = true
        button.sendAction(on: [.leftMouseDown, .leftMouseUp, .periodic])
        let action = MenuBarButtonAction(button: button) {}
        defer { action.stop() }

        XCTAssertTrue(button.target === action)
        XCTAssertNotNil(button.action)
        XCTAssertFalse(button.isContinuous)
        let configuredMask = button.sendAction(on: [])
        button.sendAction(on: NSEvent.EventTypeMask(rawValue: .init(configuredMask)))
        XCTAssertEqual(configuredMask, Int(NSEvent.EventTypeMask.leftMouseDown.rawValue))
    }

    func testRealButtonPerformClickDispatchesOneActionEachTime() {
        let button = makeButton()
        var count = 0
        let action = MenuBarButtonAction(button: button) { count += 1 }
        defer { action.stop() }

        button.performClick(nil)
        XCTAssertEqual(count, 1)
        button.performClick(nil)
        XCTAssertEqual(count, 2)
        button.performClick(nil)
        XCTAssertEqual(count, 3)
    }

    func testStopClearsOwnedTargetAndActionAndPreventsFurtherDispatch() {
        let button = makeButton()
        var count = 0
        let action = MenuBarButtonAction(button: button) { count += 1 }
        action.stop()
        action.stop()

        XCTAssertNil(button.target)
        XCTAssertNil(button.action)
        button.performClick(nil)
        XCTAssertEqual(count, 0)
    }

    func testStopPreservesAnExternallyReplacedTargetActionAndTrackingConfiguration() {
        let button = makeButton()
        var originalCount = 0
        let action = MenuBarButtonAction(button: button) { originalCount += 1 }
        let replacement = ReplacementTarget()
        let replacementSelector = #selector(ReplacementTarget.clicked(_:))
        button.target = replacement
        button.action = replacementSelector
        button.isContinuous = true
        button.sendAction(on: [.leftMouseUp, .periodic])
        action.stop()

        XCTAssertTrue(button.target === replacement)
        XCTAssertEqual(button.action, replacementSelector)
        XCTAssertTrue(button.isContinuous)
        let configuredMask = button.sendAction(on: [])
        button.sendAction(on: NSEvent.EventTypeMask(rawValue: .init(configuredMask)))
        XCTAssertEqual(configuredMask, Int(NSEvent.EventTypeMask([.leftMouseUp, .periodic]).rawValue))
        button.performClick(nil)
        XCTAssertEqual(replacement.count, 1)
        XCTAssertEqual(originalCount, 0)
    }

    func testActionDoesNotRetainItsDetachedButton() {
        var button: NSStatusBarButton? = makeButton()
        weak var releasedButton = button
        let action = MenuBarButtonAction(button: button!) {}
        button = nil

        XCTAssertNil(releasedButton)
        action.stop()
    }

    private func makeButton() -> NSStatusBarButton {
        _ = NSApplication.shared
        return NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
    }

    private final class ReplacementTarget: NSObject {
        var count = 0

        @objc func clicked(_ sender: Any?) {
            count += 1
        }
    }
}
