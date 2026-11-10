import SwiftUI
import XCTest
@testable import AlertCalendar

final class SettingsViewFormattingTests: XCTestCase {
    func testSharedLabeledControlUsesTheStandardSettingsMetrics() {
        XCTAssertEqual(SettingsVisualMetrics.inlineFieldLabelWidth, 96)
        XCTAssertEqual(SettingsVisualMetrics.calendarAlertLabelWidth, 116)
        XCTAssertGreaterThan(
            SettingsVisualMetrics.calendarAlertLabelWidth,
            SettingsVisualMetrics.inlineFieldLabelWidth
        )
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
        XCTAssertEqual(SettingsVisualMetrics.cardActionButtonSize, 28)
        XCTAssertEqual(SettingsVisualMetrics.cardActionIconSize, 11)
        XCTAssertEqual(SettingsVisualMetrics.minimumInteractiveControlSize, 28)
        XCTAssertEqual(SettingsVisualMetrics.cardActionCornerRadius, 6)
        XCTAssertEqual(SettingsCalendarCardAction.add.systemImage, "plus")
        XCTAssertEqual(SettingsCalendarCardAction.remove.systemImage, "minus")
    }

    func testSettingsSurfacesUseTheCompactMacOSHierarchy() {
        XCTAssertEqual(SettingsVisualMetrics.sidebarRowHeight, 28)
        XCTAssertEqual(SettingsVisualMetrics.sidebarIconSize, 14)
        XCTAssertLessThan(SettingsVisualMetrics.sidebarIconSize, SettingsVisualMetrics.sidebarRowHeight)
        XCTAssertEqual(SettingsVisualMetrics.generalTwoColumnMinimumWidth, 960)
        XCTAssertLessThan(
            SettingsVisualMetrics.generalTwoColumnMinimumWidth,
            1120
        )
        XCTAssertEqual(SettingsVisualMetrics.panelCornerRadius, 10)
        XCTAssertEqual(SettingsVisualMetrics.interactiveCardCornerRadius, 10)
        XCTAssertEqual(SettingsVisualMetrics.insetCornerRadius, 8)
        XCTAssertEqual(SettingsVisualMetrics.selectionRowCornerRadius, 8)
        XCTAssertEqual(SettingsVisualMetrics.panelPadding, 14)
        XCTAssertEqual(
            SettingsVisualMetrics.interactiveCardPadding,
            SettingsVisualMetrics.sectionContentSpacing
        )
    }

    func testSettingsNavigationPersistsTheActiveDestination() {
        XCTAssertEqual(
            SettingsNavigationPersistence.selectedTabKey,
            "settings.navigation.selectedTab"
        )
        XCTAssertEqual(
            SettingsNavigationPersistence.selectedFeedsSubsectionKey,
            "settings.navigation.selectedFeedsSubsection"
        )
    }

    @MainActor
    func testRetiredFeedSelectionFallsBackWithoutLosingOtherNavigationChoices() {
        let suite = "SettingsNavigationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = SettingsNavigationPersistence.selectedFeedsSubsectionKey
        defaults.set("Esports", forKey: key)
        let selection = AppStorage<SettingsView.FeedsSubsection>(
            wrappedValue: .atmosphere, key, store: defaults
        )
        XCTAssertEqual(selection.wrappedValue, .atmosphere)
        defaults.set(SettingsView.FeedsSubsection.football.rawValue, forKey: key)
        let validSelection = AppStorage<SettingsView.FeedsSubsection>(
            wrappedValue: .atmosphere, key, store: defaults
        )
        XCTAssertEqual(validSelection.wrappedValue, .football)
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

    func testDropdownWindowValueTextUsesNaturalCalendarSizedUnits() {
        XCTAssertEqual(SettingsView.dropdownWindowValueText(hours: 12), "12 hours")
        XCTAssertEqual(SettingsView.dropdownWindowValueText(hours: 24), "1 day")
        XCTAssertEqual(SettingsView.dropdownWindowValueText(hours: 144), "6 days")
        XCTAssertEqual(SettingsView.dropdownWindowValueText(hours: 168), "1 week")
        XCTAssertEqual(SettingsView.dropdownWindowValueText(hours: 504), "3 weeks")
        XCTAssertEqual(SettingsView.dropdownWindowValueText(hours: 720), "1 month")
        XCTAssertEqual(SettingsView.dropdownWindowValueText(hours: 4_320), "6 months")
    }
}
