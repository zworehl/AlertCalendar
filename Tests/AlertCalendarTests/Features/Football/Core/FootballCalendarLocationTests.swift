import CoreLocation
import EventKit
import XCTest
@testable import AlertCalendar

final class FootballCalendarLocationTests: XCTestCase {
    func testStadiumSurvivesWhenGeocodingReturnsNoCoordinates() {
        let event = EKEvent(eventStore: EKEventStore())
        event.structuredLocation = FootballCalendarLocation.structuredLocation(title: "Test Stadium", coordinate: nil)
        XCTAssertEqual(event.location, "Test Stadium")
        XCTAssertEqual(event.structuredLocation?.title, "Test Stadium")
        XCTAssertNil(event.structuredLocation?.geoLocation)
    }

    func testExistingEventWithMissingStadiumIsRepairedWithoutSavingToACalendar() {
        let event = EKEvent(eventStore: EKEventStore())
        event.location = "Test Stadium"
        event.structuredLocation = nil
        XCTAssertNil(event.location, "This reproduces the EventKit behavior behind the missing stadiums")
        let title = FootballCalendarLocation.resolvedText(reported: "Test Stadium", existing: event.location, structuredTitle: nil)!
        event.structuredLocation = FootballCalendarLocation.structuredLocation(title: title, coordinate: nil)
        XCTAssertEqual(event.location, "Test Stadium")
    }

    func testTemporaryGeocodingFailurePreservesKnownCoordinatesForSameStadium() {
        let existing = FootballCalendarLocation.structuredLocation(
            title: "Test Stadium", coordinate: CLLocationCoordinate2D(latitude: 10, longitude: -84)
        )
        let refreshed = FootballCalendarLocation.structuredLocation(title: "Test Stadium", coordinate: nil, existing: existing)
        XCTAssertEqual(refreshed.geoLocation?.coordinate.latitude, 10)
        XCTAssertEqual(refreshed.geoLocation?.coordinate.longitude, -84)
        let changedVenue = FootballCalendarLocation.structuredLocation(title: "New Stadium", coordinate: nil, existing: existing)
        XCTAssertNil(changedVenue.geoLocation, "Coordinates from a different stadium must not be copied")
    }

    func testMissingOrPlaceholderVenueDoesNotEraseExistingLocation() {
        for reported in [nil, "", "  ", "TBD", "Venue TBC"] as [String?] {
            XCTAssertEqual(FootballCalendarLocation.resolvedText(reported: reported, existing: "Known Stadium", structuredTitle: nil), "Known Stadium")
        }
        XCTAssertEqual(FootballCalendarLocation.resolvedText(reported: "New Stadium", existing: "Old Stadium", structuredTitle: nil), "New Stadium")
        XCTAssertEqual(FootballCalendarLocation.resolvedText(reported: nil, existing: nil, structuredTitle: "Known Stadium"), "Known Stadium")
        XCTAssertNil(FootballCalendarLocation.resolvedText(reported: "TBD", existing: nil, structuredTitle: nil))
    }

    func testVenueBackfillSelectsOnlyTrackedMatchesWithoutKnownStadiums() {
        let missing = FootballTestData.match(id: "missing", statusState: .scheduled)
        let placeholder = FootballTestData.match(id: "placeholder", locationText: "TBD", statusState: .scheduled)
        let known = FootballTestData.match(id: "known", locationText: "Known Stadium", statusState: .scheduled)
        let cached = FootballTestData.match(id: "cached", statusState: .scheduled)
        let cachedVenue = FootballTestData.match(id: "cached", locationText: "Cached Stadium", statusState: .scheduled)
        let untracked = FootballTestData.match(id: "untracked", statusState: .scheduled)
        let selected = CalendarMonitor.footballManagedMatchIDsNeedingVenueBackfill(
            [missing, placeholder, known, cached, untracked],
            trackedMatchIDs: ["missing", "placeholder", "known", "cached"],
            cachedMatchesByID: [cachedVenue.id: cachedVenue]
        )
        XCTAssertEqual(selected, ["missing", "placeholder"])
    }
}
