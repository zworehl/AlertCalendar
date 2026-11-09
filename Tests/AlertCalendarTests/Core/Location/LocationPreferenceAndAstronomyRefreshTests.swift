import AppKit
import CoreLocation
import EventKit
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
    func testPreferredLocationTextFallsBackToStructuredLocationTitle() {
        let value = CalendarMonitor.preferredLocationText(
            eventLocation: nil,
            structuredLocationTitle: "Apple Park Visitor Center",
            footballMatchLocation: nil
        )

        XCTAssertEqual(value, "Apple Park Visitor Center")
    }
    func testPreferredLocationTextDoesNotTreatUnknownWebLinkAsMapLocation() {
        let value = CalendarMonitor.preferredLocationText(
            eventLocation: "https://events.example.com/session/launch-review",
            footballMatchLocation: nil
        )

        XCTAssertNil(value)
    }
    func testPreferredLocationTextFallsBackToStructuredTitleWhenEventLocationIsLink() {
        let value = CalendarMonitor.preferredLocationText(
            eventLocation: "Details: https://events.example.com/session/launch-review",
            structuredLocationTitle: "Apple Park Visitor Center",
            footballMatchLocation: nil
        )

        XCTAssertEqual(value, "Apple Park Visitor Center")
    }
    func testNativeLocationCoordinateUsesEventKitStructuredLocation() {
        let event = EKEvent(eventStore: EKEventStore())
        let structuredLocation = EKStructuredLocation(title: "Apple Park Visitor Center")
        structuredLocation.geoLocation = CLLocation(latitude: 37.332_753, longitude: -122.005_372)
        event.structuredLocation = structuredLocation

        XCTAssertEqual(
            CalendarMonitor.nativeLocationCoordinate(for: event),
            ResolvedLocationCoordinate(latitude: 37.332_753, longitude: -122.005_372)
        )
    }
    func testLocationResolverPrefersNativeCoordinateOverTextLookup() async {
        let nativeCoordinate = ResolvedLocationCoordinate(latitude: 9.932_771, longitude: -84.031_712)

        let resolvedCoordinate = await LocationCoordinateResolver.shared.coordinate(
            for: "A deliberately unrelated and ambiguous location",
            preferring: nativeCoordinate
        )

        XCTAssertEqual(resolvedCoordinate, nativeCoordinate)
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
