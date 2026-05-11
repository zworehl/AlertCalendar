import XCTest
@testable import AlertCalendar

final class SettingsViewFormattingTests: XCTestCase {
    func testMenuBarRotationWindowValueTextUsesHoursAtSixtyMinutesAndAbove() {
        XCTAssertEqual(
            SettingsView.menuBarRotationWindowValueText(minutes: 60),
            "1 hour"
        )
        XCTAssertEqual(
            SettingsView.menuBarRotationWindowValueText(minutes: 120),
            "2 hours"
        )
    }
}
