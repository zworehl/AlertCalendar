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

    func testMenuBarRotationWindowStepAdvancesByHourAfterFirstHour() {
        XCTAssertEqual(
            SettingsView.adjustedMenuBarRotationWindowMinutes(
                currentValue: 55,
                incrementing: true,
                dropdownWindowHours: 13
            ),
            60
        )
        XCTAssertEqual(
            SettingsView.adjustedMenuBarRotationWindowMinutes(
                currentValue: 60,
                incrementing: true,
                dropdownWindowHours: 13
            ),
            120
        )
        XCTAssertEqual(
            SettingsView.adjustedMenuBarRotationWindowMinutes(
                currentValue: 120,
                incrementing: false,
                dropdownWindowHours: 13
            ),
            60
        )
    }

    func testMenuBarRotationWindowMaximumTracksWholeHoursBelowDropdownWindow() {
        XCTAssertEqual(
            SettingsView.maximumMenuBarRotationWindowMinutes(dropdownWindowHours: 1),
            55
        )
        XCTAssertEqual(
            SettingsView.maximumMenuBarRotationWindowMinutes(dropdownWindowHours: 2),
            60
        )
        XCTAssertEqual(
            SettingsView.maximumMenuBarRotationWindowMinutes(dropdownWindowHours: 3),
            120
        )
    }

    func testMenuBarRotationWindowNormalizationRoundsToWholeHoursAfterSixtyMinutes() {
        XCTAssertEqual(
            SettingsView.normalizedMenuBarRotationWindowMinutes(65, dropdownWindowHours: 4),
            60
        )
        XCTAssertEqual(
            SettingsView.normalizedMenuBarRotationWindowMinutes(110, dropdownWindowHours: 4),
            120
        )
    }

    func testContextualPreviewLeadMaximumTracksDropdownWindow() {
        XCTAssertEqual(
            SettingsView.maximumContextualPreviewLeadMinutes(dropdownWindowHours: 1),
            60
        )
        XCTAssertEqual(
            SettingsView.maximumContextualPreviewLeadMinutes(dropdownWindowHours: 3),
            180
        )
    }

    func testContextualPreviewLeadNormalizationSupportsMixedMinuteSteps() {
        XCTAssertEqual(
            SettingsView.normalizedContextualPreviewLeadMinutes(62, dropdownWindowHours: 6),
            60
        )
        XCTAssertEqual(
            SettingsView.normalizedContextualPreviewLeadMinutes(83, dropdownWindowHours: 6),
            60
        )
        XCTAssertEqual(
            SettingsView.normalizedContextualPreviewLeadMinutes(194, dropdownWindowHours: 6),
            180
        )
    }
}
