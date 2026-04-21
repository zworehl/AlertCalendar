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

    func testShouldIncludeAllDayItemKeepsCurrentAllDayEventVisible() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 21, hour: 18))!
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 21))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 22))!

        XCTAssertTrue(
            CalendarMonitor.shouldIncludeAllDayItem(
                startDate: startDate,
                endDate: endDate,
                now: now,
                futureWindowEnd: now.addingTimeInterval(6 * 60 * 60),
                calendar: calendar
            )
        )
    }

    func testShouldIncludeAllDayItemIncludesNextDayEventInsideWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 21, hour: 18))!
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 22))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 23))!

        XCTAssertTrue(
            CalendarMonitor.shouldIncludeAllDayItem(
                startDate: startDate,
                endDate: endDate,
                now: now,
                futureWindowEnd: now.addingTimeInterval(24 * 60 * 60),
                calendar: calendar
            )
        )
    }

    func testShouldIncludeAllDayItemExcludesNextDayEventOutsideWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 21, hour: 18))!
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 23))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 24))!

        XCTAssertFalse(
            CalendarMonitor.shouldIncludeAllDayItem(
                startDate: startDate,
                endDate: endDate,
                now: now,
                futureWindowEnd: now.addingTimeInterval(24 * 60 * 60),
                calendar: calendar
            )
        )
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

    func testMeetingAttendeesNormalizedDeduplicatesAndSortsByResponse() {
        let attendees = MeetingAttendee.normalized([
            MeetingAttendee(
                id: "warner@getzilker.com",
                displayText: "Warner",
                emailAddress: nil,
                response: .pending
            ),
            MeetingAttendee(
                id: "warner@getzilker.com",
                displayText: "warner@getzilker.com",
                emailAddress: "warner@getzilker.com",
                response: .accepted
            ),
            MeetingAttendee(
                id: "brett@getzilker.com",
                displayText: "brett@getzilker.com",
                emailAddress: "brett@getzilker.com",
                response: .tentative
            ),
            MeetingAttendee(
                id: "olivia@getzilker.com",
                displayText: "olivia@getzilker.com",
                emailAddress: "olivia@getzilker.com",
                response: .declined
            ),
            MeetingAttendee(
                id: "carlos@getzilker.com",
                displayText: "carlos@getzilker.com",
                emailAddress: "carlos@getzilker.com",
                response: .pending
            ),
        ])

        XCTAssertEqual(attendees.map(\.displayText), [
            "Warner",
            "brett@getzilker.com",
            "olivia@getzilker.com",
            "carlos@getzilker.com",
        ])
        XCTAssertEqual(attendees.map(\.response), [
            .accepted,
            .tentative,
            .declined,
            .pending,
        ])
    }
}
