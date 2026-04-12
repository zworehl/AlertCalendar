import AppKit
import Foundation
import XCTest
@testable import AlertCalendar

final class AlertCalendarModelTests: XCTestCase {
    func testAstronomyMomentParsesTrimmedCaseInsensitiveTitle() {
        XCTAssertEqual(AstronomyMoment(eventTitle: "  Solar Noon  "), .solarNoon)
        XCTAssertEqual(AstronomyMoment(eventTitle: "SUNSET"), .sunset)
        XCTAssertEqual(AstronomyMoment(eventTitle: " full moon "), .fullMoon)
        XCTAssertEqual(AstronomyMoment(eventTitle: "PERIHELION"), .perihelion)
        XCTAssertEqual(AstronomyMoment(eventTitle: "  march equinox "), .marchEquinox)
        XCTAssertNil(AstronomyMoment(eventTitle: "moonrise"))
    }

    func testAstronomyMomentPresentationMetadata() {
        XCTAssertEqual(AstronomyMoment.sunrise.title, "Sunrise")
        XCTAssertEqual(AstronomyMoment.solarMidnight.fallbackSymbolName, "moon.stars.fill")
        XCTAssertEqual(AstronomyMoment.solarNoon.svgAssetName, "solar-noon")
        XCTAssertEqual(AstronomyMoment.newMoon.svgAssetName, "moon-new")
        XCTAssertEqual(AstronomyMoment.fullMoon.svgAssetName, "moon-full")
        XCTAssertNil(AstronomyMoment.sunset.svgAssetName)
        XCTAssertEqual(AstronomyMoment.fullMoon.title, "Full Moon")
        XCTAssertEqual(AstronomyMoment.perihelion.title, "Perihelion")
        XCTAssertEqual(AstronomyMoment.decemberSolstice.title, "December Solstice")
    }

    func testUpcomingItemNotificationKeyUsesCoreFields() {
        let start = Date(timeIntervalSince1970: 1_710_000_000)
        let item = UpcomingItem(
            id: "abc123",
            title: "Daily sync",
            date: start,
            endDate: nil,
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: "cal-1",
            calendarName: "Work",
            calendarColor: .systemBlue,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )

        XCTAssertEqual(item.notificationKey, "abc123|1710000000|Event|false")
    }

    func testMenuMarkerStyleEqualityForColorAndSymbolMarkers() {
        XCTAssertEqual(MenuMarkerStyle.color(.systemBlue), MenuMarkerStyle.color(.systemBlue))
        XCTAssertNotEqual(MenuMarkerStyle.color(.systemBlue), MenuMarkerStyle.color(.systemRed))
        XCTAssertEqual(MenuMarkerStyle.sunrise, MenuMarkerStyle.sunrise)
        XCTAssertNotEqual(MenuMarkerStyle.sunrise, MenuMarkerStyle.sunset)
        XCTAssertEqual(MenuMarkerStyle.fullMoon, MenuMarkerStyle.fullMoon)
        XCTAssertNotEqual(MenuMarkerStyle.perihelion, MenuMarkerStyle.aphelion)
        XCTAssertNotEqual(MenuMarkerStyle.marchEquinox, MenuMarkerStyle.decemberSolstice)
    }

    func testAvailableCalendarEqualityComparesColorAndMetadata() {
        let lhs = AvailableCalendar(
            id: "1",
            title: "Personal",
            color: .systemGreen,
            kind: .event,
            accountTitle: "iCloud",
            isSubscribed: false
        )
        let rhs = AvailableCalendar(
            id: "1",
            title: "Personal",
            color: .systemGreen,
            kind: .event,
            accountTitle: "iCloud",
            isSubscribed: false
        )
        let different = AvailableCalendar(
            id: "1",
            title: "Personal",
            color: .systemOrange,
            kind: .event,
            accountTitle: "iCloud",
            isSubscribed: false
        )

        XCTAssertEqual(lhs, rhs)
        XCTAssertNotEqual(lhs, different)
    }
}
