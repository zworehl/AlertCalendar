import XCTest
@testable import AlertCalendar

final class SettingsViewFormattingTests: XCTestCase {
    func testSharedLabeledControlUsesTheStandardSettingsMetrics() {
        XCTAssertEqual(SettingsVisualMetrics.inlineFieldLabelWidth, 96)
        XCTAssertEqual(SettingsVisualMetrics.inlineFieldSpacing, 10)
        XCTAssertEqual(SettingsVisualMetrics.stackedFieldSpacing, 4)
        XCTAssertEqual(
            SettingsLabeledControlLayout.standardInline,
            .inline(labelWidth: SettingsVisualMetrics.inlineFieldLabelWidth)
        )
    }

    func testSharedCheckboxGroupsUseConsistentResponsiveMetrics() {
        XCTAssertEqual(SettingsVisualMetrics.checkboxGroupItemSpacing, 18)
        XCTAssertEqual(SettingsVisualMetrics.checkboxGroupGridSpacing, 10)
        XCTAssertEqual(SettingsVisualMetrics.checkboxGroupMinimumItemWidth, 150)
        XCTAssertEqual(SettingsVisualMetrics.checkboxGroupMaximumItemWidth, 220)
        XCTAssertEqual(SettingsVisualMetrics.inlineDividerHeight, 36)
        XCTAssertNotEqual(SettingsLabeledCheckboxGroupLayout.inline, .adaptive)
    }

    func testSettingsCalendarCardsShareTheFootballActionMetrics() {
        XCTAssertEqual(SettingsVisualMetrics.cardActionButtonSize, 18)
        XCTAssertEqual(SettingsVisualMetrics.cardActionIconSize, 9)
        XCTAssertEqual(SettingsVisualMetrics.cardActionCornerRadius, 6)
        XCTAssertEqual(SettingsCalendarCardAction.add.systemImage, "plus")
        XCTAssertEqual(SettingsCalendarCardAction.remove.systemImage, "minus")
    }

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
