import XCTest
@testable import AlertCalendar

final class AppSettingsRulesTests: XCTestCase {
    func testDropdownItemLimitUsesFiveItemStepsThroughOneHundred() {
        XCTAssertEqual(AppSettingsRules.dropdownListItemOptions, Array(stride(from: 5, through: 100, by: 5)))
        XCTAssertEqual(AppSettingsRules.defaultMaximumDropdownItems, 10)
        XCTAssertEqual(AppSettingsRules.normalizedMaximumDropdownItems(0), 10)
        XCTAssertEqual(AppSettingsRules.normalizedMaximumDropdownItems(8), 10)
        XCTAssertEqual(AppSettingsRules.normalizedMaximumDropdownItems(97), 95)
        XCTAssertEqual(AppSettingsRules.normalizedMaximumDropdownItems(500), 100)
    }

    func testDropdownWindowAdvancesFromHoursToDaysWeeksAndMonths() {
        XCTAssertEqual(AppSettingsRules.adjustedDropdownWindowHours(currentValue: 23, incrementing: true), 24)
        XCTAssertEqual(AppSettingsRules.adjustedDropdownWindowHours(currentValue: 144, incrementing: true), 168)
        XCTAssertEqual(AppSettingsRules.adjustedDropdownWindowHours(currentValue: 504, incrementing: true), 720)
        XCTAssertEqual(AppSettingsRules.adjustedDropdownWindowHours(currentValue: 720, incrementing: false), 504)
        XCTAssertEqual(AppSettingsRules.adjustedDropdownWindowHours(currentValue: 4_320, incrementing: true), 4_320)
        XCTAssertEqual(AppSettingsRules.normalizedDropdownWindowHours(0), 24)
        XCTAssertEqual(AppSettingsRules.normalizedDropdownWindowHours(700), 720)
    }

    func testAgendaSummaryWordOptionsAndNormalization() {
        XCTAssertEqual(
            AppSettingsRules.agendaSummaryMaximumWordOptions,
            [30, 40, 50, 60, 70, 80, 90, 100]
        )
        XCTAssertEqual(AppSettingsRules.defaultAgendaSummaryMaximumWords, 60)
        XCTAssertEqual(AppSettingsRules.normalizedAgendaSummaryMaximumWords(0), 60)
        XCTAssertEqual(AppSettingsRules.normalizedAgendaSummaryMaximumWords(34), 30)
        XCTAssertEqual(AppSettingsRules.normalizedAgendaSummaryMaximumWords(76), 80)
        XCTAssertEqual(AppSettingsRules.normalizedAgendaSummaryMaximumWords(500), 100)
    }

    func testAppleIntelligenceTitleRewriteRequiresAtLeastTenCharacters() {
        XCTAssertFalse(AppSettingsRules.allowsAppleIntelligenceTitleRewrite(maximumCharacters: 8))
        XCTAssertFalse(AppSettingsRules.allowsAppleIntelligenceTitleRewrite(maximumCharacters: 9))
        XCTAssertTrue(AppSettingsRules.allowsAppleIntelligenceTitleRewrite(maximumCharacters: 10))
        XCTAssertTrue(AppSettingsRules.allowsAppleIntelligenceTitleRewrite(maximumCharacters: 22))
    }

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

    func testMenuBarRotationWindowStepAdvancesAndRetreatsByFiveMinutesBelowFirstHour() {
        XCTAssertEqual(
            AppSettingsRules.adjustedMenuBarRotationWindowMinutes(
                currentValue: 10,
                incrementing: true,
                dropdownWindowHours: 13
            ),
            15
        )
        XCTAssertEqual(
            AppSettingsRules.adjustedMenuBarRotationWindowMinutes(
                currentValue: 60,
                incrementing: false,
                dropdownWindowHours: 13
            ),
            55
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
