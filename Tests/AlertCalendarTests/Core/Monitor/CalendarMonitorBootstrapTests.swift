import XCTest
@testable import AlertCalendar

final class CalendarMonitorBootstrapTests: XCTestCase {
    func testEmptyMenuBarQueueWithEnabledAccessKeepsLoadingUntilConfirmationRefresh() {
        XCTAssertTrue(
            CalendarMonitor.shouldConfirmInitialMenuBarSnapshot(
                hasEnabledCalendarSourceAccess: true,
                menuBarQueueIsEmpty: true
            )
        )
    }

    func testEligibleMenuBarItemOrMissingEnabledAccessDoesNotDelayInitialPresentation() {
        XCTAssertFalse(
            CalendarMonitor.shouldConfirmInitialMenuBarSnapshot(
                hasEnabledCalendarSourceAccess: true,
                menuBarQueueIsEmpty: false
            )
        )
        XCTAssertFalse(
            CalendarMonitor.shouldConfirmInitialMenuBarSnapshot(
                hasEnabledCalendarSourceAccess: false,
                menuBarQueueIsEmpty: true
            )
        )
    }

    func testNotificationAuthorizationIsNeededOnlyWhenAtLeastOneNotificationIsEnabled() {
        var settings = AppSettings.defaults
        XCTAssertTrue(CalendarMonitor.needsNotificationAuthorization(settings: settings))

        settings.enableGameSaleAutoAddNotifications = false
        settings.enableFootballGoalNotifications = false
        settings.enableFootballDisallowedGoalNotifications = false
        settings.enableFootballFinalNotifications = false
        settings.enableFootballAutoAddNotifications = false
        XCTAssertFalse(CalendarMonitor.needsNotificationAuthorization(settings: settings))
    }
}
