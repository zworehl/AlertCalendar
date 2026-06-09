import Foundation
import XCTest
@testable import AlertCalendar

final class FootballEventTimeZoneTests: XCTestCase {
    func testFootballEventTimeZoneNeedsUpdateWhenMissingDesiredTimeZone() {
        let desiredTimeZone = TimeZone(identifier: "Europe/Madrid")

        XCTAssertTrue(
            CalendarMonitor.footballEventTimeZoneNeedsUpdate(
                currentTimeZone: nil,
                desiredTimeZone: desiredTimeZone
            )
        )
    }

    func testFootballEventTimeZoneDoesNotNeedUpdateWhenIdentifiersMatch() {
        let currentTimeZone = TimeZone(identifier: "Europe/Madrid")
        let desiredTimeZone = TimeZone(identifier: "Europe/Madrid")

        XCTAssertFalse(
            CalendarMonitor.footballEventTimeZoneNeedsUpdate(
                currentTimeZone: currentTimeZone,
                desiredTimeZone: desiredTimeZone
            )
        )
    }

    func testFootballEventTimeZoneNeedsUpdateWhenIdentifiersDiffer() {
        let currentTimeZone = TimeZone(identifier: "America/Costa_Rica")
        let desiredTimeZone = TimeZone(identifier: "Europe/Madrid")

        XCTAssertTrue(
            CalendarMonitor.footballEventTimeZoneNeedsUpdate(
                currentTimeZone: currentTimeZone,
                desiredTimeZone: desiredTimeZone
            )
        )
    }
}
