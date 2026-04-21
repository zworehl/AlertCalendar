import XCTest
@testable import AlertCalendar

final class MenuBarStateTests: XCTestCase {
    func testMenuBarEmptyStateTextUsesRotationWindowWhenLaterItemsExist() {
        XCTAssertEqual(
            CalendarMonitor.menuBarEmptyStateText(
                menuBarRotationWindowMinutes: 60,
                hasLaterItemsInDropdownWindow: true
            ),
            "No items in next 1h"
        )
    }

    func testMenuBarEmptyStateTextFallsBackToGenericEmptyStateWhenNothingElseExists() {
        XCTAssertEqual(
            CalendarMonitor.menuBarEmptyStateText(
                menuBarRotationWindowMinutes: 60,
                hasLaterItemsInDropdownWindow: false
            ),
            "No upcoming items"
        )
    }

    func testMenuBarRotationWindowDescriptionFormatsCompoundDurations() {
        XCTAssertEqual(
            CalendarMonitor.menuBarRotationWindowDescription(minutes: 90),
            "1h 30m"
        )
    }
}
