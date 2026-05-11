import XCTest
@testable import AlertCalendar

final class AppSettingsRulesTests: XCTestCase {
    func testMenuBarRotationWindowStepAdvancesByHourAfterFirstHour() {
        XCTAssertEqual(
            AppSettingsRules.adjustedMenuBarRotationWindowMinutes(
                currentValue: 55,
                incrementing: true,
                dropdownWindowHours: 13
            ),
            60
        )
        XCTAssertEqual(
            AppSettingsRules.adjustedMenuBarRotationWindowMinutes(
                currentValue: 60,
                incrementing: true,
                dropdownWindowHours: 13
            ),
            120
        )
        XCTAssertEqual(
            AppSettingsRules.adjustedMenuBarRotationWindowMinutes(
                currentValue: 120,
                incrementing: false,
                dropdownWindowHours: 13
            ),
            60
        )
    }

    func testMenuBarRotationWindowMaximumTracksWholeHoursBelowDropdownWindow() {
        XCTAssertEqual(
            AppSettingsRules.maximumMenuBarRotationWindowMinutes(dropdownWindowHours: 1),
            55
        )
        XCTAssertEqual(
            AppSettingsRules.maximumMenuBarRotationWindowMinutes(dropdownWindowHours: 2),
            60
        )
        XCTAssertEqual(
            AppSettingsRules.maximumMenuBarRotationWindowMinutes(dropdownWindowHours: 3),
            120
        )
    }

    func testMenuBarRotationWindowNormalizationRoundsToWholeHoursAfterSixtyMinutes() {
        XCTAssertEqual(
            AppSettingsRules.normalizedMenuBarRotationWindowMinutes(65, dropdownWindowHours: 4),
            60
        )
        XCTAssertEqual(
            AppSettingsRules.normalizedMenuBarRotationWindowMinutes(110, dropdownWindowHours: 4),
            120
        )
    }

    func testContextualPreviewLeadMaximumTracksDropdownWindow() {
        XCTAssertEqual(
            AppSettingsRules.maximumContextualPreviewLeadMinutes(dropdownWindowHours: 1),
            60
        )
        XCTAssertEqual(
            AppSettingsRules.maximumContextualPreviewLeadMinutes(dropdownWindowHours: 3),
            180
        )
    }

    func testContextualPreviewLeadNormalizationSupportsMixedMinuteSteps() {
        XCTAssertEqual(
            AppSettingsRules.normalizedContextualPreviewLeadMinutes(62, dropdownWindowHours: 6),
            60
        )
        XCTAssertEqual(
            AppSettingsRules.normalizedContextualPreviewLeadMinutes(83, dropdownWindowHours: 6),
            60
        )
        XCTAssertEqual(
            AppSettingsRules.normalizedContextualPreviewLeadMinutes(194, dropdownWindowHours: 6),
            180
        )
    }
}
