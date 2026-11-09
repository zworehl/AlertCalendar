import XCTest
@testable import AlertCalendar

final class MenuDropdownPlacementTests: XCTestCase {
    func testCompactAndExpandedContentsKeepTheSameTopAndRightAnchor() {
        let button = CGRect(x: 1100, y: 876, width: 160, height: 24)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 876)
        let compact = MenuDropdownPlacement.frame(contentSize: CGSize(width: 360, height: 200),
                                                  buttonFrame: button, visibleFrame: visible)
        let expanded = MenuDropdownPlacement.frame(contentSize: CGSize(width: 708, height: 600),
                                                   buttonFrame: button, visibleFrame: visible)
        XCTAssertEqual(compact.maxY, 872)
        XCTAssertEqual(expanded.maxY, compact.maxY)
        XCTAssertEqual(compact.maxX, button.maxX)
        XCTAssertEqual(expanded.maxX, button.maxX)
    }

    func testLeftAndRightEdgeItemsKeepPanelInsideTheirDisplay() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 876)
        for button in [CGRect(x: 0, y: 876, width: 80, height: 24),
                       CGRect(x: 1410, y: 876, width: 100, height: 24)] {
            let frame = MenuDropdownPlacement.frame(contentSize: CGSize(width: 708, height: 600),
                                                    buttonFrame: button, visibleFrame: visible)
            XCTAssertGreaterThanOrEqual(frame.minX, visible.minX + 4)
            XCTAssertLessThanOrEqual(frame.maxX, visible.maxX - 4)
        }
    }

    func testSmallDisplayCapsContentAboveTheDock() {
        let visible = CGRect(x: 0, y: 60, width: 640, height: 390)
        let frame = MenuDropdownPlacement.frame(contentSize: CGSize(width: 708, height: 800),
                                                buttonFrame: CGRect(x: 550, y: 450, width: 80, height: 24),
                                                visibleFrame: visible)
        XCTAssertEqual(frame.width, 632)
        XCTAssertEqual(frame.minY, 64)
        XCTAssertEqual(frame.maxY, 446)
    }

    func testSecondaryDisplayUsesDesktopPointsIncludingNegativeCoordinates() {
        let visible = CGRect(x: -1920, y: -180, width: 1920, height: 1056)
        let frame = MenuDropdownPlacement.frame(contentSize: CGSize(width: 708, height: 587),
                                                buttonFrame: CGRect(x: -220, y: 876, width: 140, height: 24),
                                                visibleFrame: visible)
        XCTAssertEqual(frame, CGRect(x: -788, y: 285, width: 708, height: 587))
    }
}
