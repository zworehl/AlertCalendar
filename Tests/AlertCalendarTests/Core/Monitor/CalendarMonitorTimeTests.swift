import Foundation
import XCTest
@testable import AlertCalendar

final class CalendarMonitorTimeTests: XCTestCase {
    func testHasElapsedTreatsMissingDateAsDue() {
        XCTAssertTrue(
            CalendarMonitorTime.hasElapsed(
                since: nil,
                now: Date(timeIntervalSince1970: 100),
                interval: 60
            )
        )
    }

    func testHasElapsedUsesIntervalBoundary() {
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertFalse(
            CalendarMonitorTime.hasElapsed(
                since: Date(timeIntervalSince1970: 41),
                now: now,
                interval: 60
            )
        )
        XCTAssertTrue(
            CalendarMonitorTime.hasElapsed(
                since: Date(timeIntervalSince1970: 40),
                now: now,
                interval: 60
            )
        )
    }

    func testNanosecondsUntilClampsPastDateAndHonorsMinimumDelay() {
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(
            CalendarMonitorTime.nanoseconds(until: Date(timeIntervalSince1970: 99), now: now),
            0
        )
        XCTAssertEqual(
            CalendarMonitorTime.nanoseconds(
                until: Date(timeIntervalSince1970: 99),
                now: now,
                minimumDelay: 0.25
            ),
            250_000_000
        )
    }
}
