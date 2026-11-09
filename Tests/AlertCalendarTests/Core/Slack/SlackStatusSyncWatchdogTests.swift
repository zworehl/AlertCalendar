import XCTest
@testable import AlertCalendar

final class SlackStatusSyncWatchdogTests: XCTestCase {
    func testWatchdogAllowsLongSyncWithProgressAndTimesOutStalledProgress() {
        let now = Date(timeIntervalSince1970: 1_777_000_100)
        XCTAssertFalse(CalendarMonitor.slackStatusSyncTaskTimedOut(
            startedAt: now.addingTimeInterval(-120),
            lastProgressAt: now.addingTimeInterval(-20), now: now, timeout: 45
        ))
        XCTAssertTrue(CalendarMonitor.slackStatusSyncTaskTimedOut(
            startedAt: now.addingTimeInterval(-120),
            lastProgressAt: now.addingTimeInterval(-45), now: now, timeout: 45
        ))
    }

}
