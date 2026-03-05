import AppKit
import Foundation
import XCTest
@testable import AlertCalendar

final class AlertCalendarAdditionalModelTests: XCTestCase {
    func testActiveEventDisplayModeMetadataIsStable() {
        XCTAssertEqual(ActiveEventDisplayMode.allCases.map(\.id), ["remaining", "elapsed"])
        XCTAssertEqual(ActiveEventDisplayMode.remaining.title, "Show time remaining")
        XCTAssertEqual(ActiveEventDisplayMode.elapsed.title, "Show elapsed time")
    }

    func testCalendarColorPaletteOptionsHaveUniqueIDsAndKnownFallback() {
        let options = CalendarColorPalette.options
        let uniqueIDs = Set(options.map(\.id))

        XCTAssertEqual(options.count, 12)
        XCTAssertEqual(uniqueIDs.count, options.count)

        let mint = CalendarColorPalette.color(for: "mint")
        let expectedMint = options.first(where: { $0.id == "mint" })!.color
        XCTAssertTrue(mint.isEqual(expectedMint))

        let fallback = CalendarColorPalette.color(for: "does-not-exist")
        let expectedFallback = options.first(where: { $0.id == "blue" })!.color
        XCTAssertTrue(fallback.isEqual(expectedFallback))
    }

    func testDefaultsKeysAreUniqueAndComplete() {
        let keys = [
            DefaultsKeys.includeEvents,
            DefaultsKeys.includeAllDayEvents,
            DefaultsKeys.includeReminders,
            DefaultsKeys.includeWeather,
            DefaultsKeys.includeAstronomy,
            DefaultsKeys.useAutomaticAstronomyLocation,
            DefaultsKeys.astronomyColorID,
            DefaultsKeys.astronomyLatitude,
            DefaultsKeys.astronomyLongitude,
            DefaultsKeys.selectedEventCalendarIDs,
            DefaultsKeys.selectedReminderCalendarIDs,
            DefaultsKeys.weekdayOnlyEventCalendarIDs,
            DefaultsKeys.weekdayOnlyReminderCalendarIDs,
            DefaultsKeys.lookAheadHours,
            DefaultsKeys.alertLeadMinutes,
            DefaultsKeys.nearUpcomingAlternateMinutes,
            DefaultsKeys.concurrentEventRotationSeconds,
            DefaultsKeys.useSimplifiedCountdown,
            DefaultsKeys.activeEventDisplayMode,
            DefaultsKeys.useEventTitleEllipsis,
            DefaultsKeys.eventTitleMaxCharacters,
            DefaultsKeys.maxListItems,
            DefaultsKeys.enableBlinkAlert,
            DefaultsKeys.menuBarFontSize,
            DefaultsKeys.skippedItemKeys,
            DefaultsKeys.skippedWeatherUntil,
        ]

        XCTAssertEqual(keys.count, 26)
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertTrue(keys.contains("activeEventDisplayMode"))
        XCTAssertTrue(keys.contains("menuBarFontSize"))
    }

    func testUpcomingItemEqualityTracksKindAndMeetingURL() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let meetingURL = URL(string: "https://example.com/room")!

        let base = UpcomingItem(
            id: "item-1",
            title: "Planning",
            date: start,
            endDate: start.addingTimeInterval(1800),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: 12,
            locationText: "Room 4",
            meetingURL: meetingURL,
            calendarID: "cal-1",
            calendarName: "Work",
            calendarColor: NSColor(calibratedRed: 0.20, green: 0.50, blue: 0.90, alpha: 1),
            kind: .event
        )

        let same = UpcomingItem(
            id: "item-1",
            title: "Planning",
            date: start,
            endDate: start.addingTimeInterval(1800),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: 12,
            locationText: "Room 4",
            meetingURL: meetingURL,
            calendarID: "cal-1",
            calendarName: "Work",
            calendarColor: NSColor(calibratedRed: 0.20, green: 0.50, blue: 0.90, alpha: 1),
            kind: .event
        )

        let differentKind = UpcomingItem(
            id: "item-1",
            title: "Planning",
            date: start,
            endDate: start.addingTimeInterval(1800),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: 12,
            locationText: "Room 4",
            meetingURL: meetingURL,
            calendarID: "cal-1",
            calendarName: "Work",
            calendarColor: NSColor(calibratedRed: 0.20, green: 0.50, blue: 0.90, alpha: 1),
            kind: .reminder
        )

        let withoutMeetingURL = UpcomingItem(
            id: "item-1",
            title: "Planning",
            date: start,
            endDate: start.addingTimeInterval(1800),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: 12,
            locationText: "Room 4",
            meetingURL: nil,
            calendarID: "cal-1",
            calendarName: "Work",
            calendarColor: NSColor(calibratedRed: 0.20, green: 0.50, blue: 0.90, alpha: 1),
            kind: .event
        )

        XCTAssertEqual(base, same)
        XCTAssertNotEqual(base, differentKind)
        XCTAssertNotEqual(base, withoutMeetingURL)
    }

    func testMenuMarkerStyleDistinguishesSymbolFamilies() {
        XCTAssertEqual(MenuMarkerStyle.allDay(.systemBlue), MenuMarkerStyle.allDay(.systemBlue))
        XCTAssertNotEqual(MenuMarkerStyle.color(.systemBlue), MenuMarkerStyle.reminder(.systemBlue))
        XCTAssertNotEqual(MenuMarkerStyle.birthday(.systemPink), MenuMarkerStyle.allDay(.systemPink))
    }

    func testAstronomyMomentsExposeCompleteMetadata() {
        XCTAssertEqual(AstronomyMoment.allCases.count, 4)
        XCTAssertEqual(Set(AstronomyMoment.allCases.map(\.title)).count, 4)
        XCTAssertTrue(AstronomyMoment.allCases.allSatisfy { !$0.fallbackSymbolName.isEmpty })
        XCTAssertEqual(AstronomyMoment.allCases.filter { $0.svgAssetName != nil }.count, 2)
    }
}
