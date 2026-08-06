import AppKit
import Foundation
import XCTest
@testable import AlertCalendar

final class LocationPreferenceAndAstronomyRefreshTests: AlertCalendarModelTestCase {
    func testPreferredLocationTextUsesFootballVenueWhenAvailable() {
        let value = CalendarMonitor.preferredLocationText(
            eventLocation: "Buenos Aires, Argentina",
            footballMatchLocation: "Alberto Jose Armando (La Bombonera), Buenos Aires, Argentina"
        )

        XCTAssertEqual(value, "Alberto Jose Armando (La Bombonera), Buenos Aires, Argentina")
    }
    func testPreferredLocationTextFallsBackToEventLocation() {
        let value = CalendarMonitor.preferredLocationText(
            eventLocation: "Mercedes-Benz Stadium, Atlanta, Georgia, USA",
            footballMatchLocation: nil
        )

        XCTAssertEqual(value, "Mercedes-Benz Stadium, Atlanta, Georgia, USA")
    }
    func testAutomaticAstronomyLocationHourlyRefreshWaitsOneHour() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertFalse(
            CalendarMonitor.shouldRefreshAutomaticAstronomyLocation(
                lastAttemptDate: now.addingTimeInterval(-(59 * 60)),
                now: now,
                trigger: .hourly
            )
        )
        XCTAssertTrue(
            CalendarMonitor.shouldRefreshAutomaticAstronomyLocation(
                lastAttemptDate: now.addingTimeInterval(-(60 * 60)),
                now: now,
                trigger: .hourly
            )
        )
    }
    func testAutomaticAstronomyLocationAppActivationWaitsFifteenMinutes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertFalse(
            CalendarMonitor.shouldRefreshAutomaticAstronomyLocation(
                lastAttemptDate: now.addingTimeInterval(-(14 * 60 + 59)),
                now: now,
                trigger: .appActivation
            )
        )
        XCTAssertTrue(
            CalendarMonitor.shouldRefreshAutomaticAstronomyLocation(
                lastAttemptDate: now.addingTimeInterval(-15 * 60),
                now: now,
                trigger: .appActivation
            )
        )
    }
    func testAutomaticAstronomyLocationWiFiChangeRefreshesImmediately() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertTrue(
            CalendarMonitor.shouldRefreshAutomaticAstronomyLocation(
                lastAttemptDate: now.addingTimeInterval(-5),
                now: now,
                trigger: .wifiNetworkChange
            )
        )
    }}
