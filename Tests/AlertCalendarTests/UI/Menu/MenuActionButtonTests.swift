import AppKit
import SwiftUI
import XCTest
@testable import AlertCalendar

@MainActor
final class MenuActionButtonTests: XCTestCase {
    func testNativeButtonsRespectTheirReservedWidthAndSpacing() throws {
        let buttonSize = MenuActionControlMetrics.minimumHitTargetSize
        let spacing = MenuActionControlMetrics.controlSpacing
        let showsFirstAction = true
        let remainingActions = ["Complete"]
        let content = ZStack(alignment: .trailing) {
            Color.clear
            MenuActionButtonGroup {
                if showsFirstAction {
                    MenuActionButton(systemImage: "link", toolTip: "Open link", accessibilityLabel: "Open link") {}
                        .frame(width: buttonSize, height: buttonSize)
                }
                ForEach(remainingActions, id: \.self) { label in
                    MenuActionButton(systemImage: "forward.end", toolTip: "Skip", accessibilityLabel: label) {}
                        .frame(width: buttonSize, height: buttonSize)
                }
            }
            .frame(minWidth: buttonSize, alignment: .trailing)
        }
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: buttonSize * 4, height: buttonSize)
        hostingView.layoutSubtreeIfNeeded()

        func buttons(in view: NSView) -> [MenuActionNSButton] {
            if let button = view as? MenuActionNSButton { return [button] }
            return view.subviews.flatMap { buttons(in: $0) }
        }
        let frames = buttons(in: hostingView).map { $0.convert($0.bounds, to: hostingView) }
            .sorted { $0.minX < $1.minX }
        XCTAssertEqual(frames.count, 2)
        let first = try XCTUnwrap(frames.first)
        let last = try XCTUnwrap(frames.last)
        XCTAssertEqual(first.width, buttonSize, accuracy: 0.5)
        XCTAssertEqual(last.width, buttonSize, accuracy: 0.5)
        XCTAssertEqual(last.minX - first.maxX, spacing, accuracy: 0.5)
    }

    func testNativeButtonKeepsTooltipAndUsesLatestActionAfterRefresh() {
        let button = MenuActionNSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        var oldActionCount = 0
        var currentActionCount = 0
        button.configure(
            systemImage: "checkmark.circle",
            toolTip: "Complete reminder",
            accessibilityLabel: "Complete first reminder",
            isEnabled: true
        ) { oldActionCount += 1 }
        button.configure(
            systemImage: "checkmark.circle",
            toolTip: "Complete reminder",
            accessibilityLabel: "Complete current reminder",
            isEnabled: true
        ) { currentActionCount += 1 }

        XCTAssertEqual(button.toolTip, "Complete reminder")
        XCTAssertEqual(button.accessibilityLabel(), "Complete current reminder")
        XCTAssertEqual(button.imagePosition, .imageOnly)
        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.title, "")
        button.performClick(nil)
        XCTAssertEqual(oldActionCount, 0)
        XCTAssertEqual(currentActionCount, 1)
    }

    func testDisabledActionCannotRunUntilReenabled() {
        let button = MenuActionNSButton(frame: .zero)
        var actionCount = 0
        for isEnabled in [false, true] {
            button.configure(
                systemImage: "forward.end",
                toolTip: "Skip this item",
                accessibilityLabel: "Skip reminder",
                isEnabled: isEnabled
            ) { actionCount += 1 }
            button.performClick(nil)
            XCTAssertEqual(actionCount, isEnabled ? 1 : 0)
            XCTAssertEqual(button.toolTip, "Skip this item")
        }
    }
}
