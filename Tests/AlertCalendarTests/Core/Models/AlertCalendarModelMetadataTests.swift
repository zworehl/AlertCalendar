import AppKit
import Foundation
import XCTest
@testable import AlertCalendar

final class AlertCalendarModelMetadataTests: AlertCalendarModelTestCase {
    func testActiveEventDisplayModeMetadataIsStable() {
        XCTAssertEqual(ActiveEventDisplayMode.allCases.map(\.id), ["remaining", "elapsed"])
        XCTAssertEqual(ActiveEventDisplayMode.remaining.title, "Show time remaining")
        XCTAssertEqual(ActiveEventDisplayMode.elapsed.title, "Show elapsed time")
    }
    func testEventParticipationStatusVisualMetadataMatchesAppleCalendarStyle() {
        XCTAssertFalse(EventParticipationStatus.accepted.usesTexturedFill)
        XCTAssertTrue(EventParticipationStatus.tentative.usesTexturedFill)
        XCTAssertTrue(EventParticipationStatus.pending.usesTexturedFill)
        XCTAssertTrue(EventParticipationStatus.declined.usesTexturedFill)

        XCTAssertGreaterThan(EventParticipationStatus.accepted.appleCalendarTextAlpha, EventParticipationStatus.pending.appleCalendarTextAlpha)
        XCTAssertGreaterThan(EventParticipationStatus.pending.appleCalendarStripeAlpha, 0)
        XCTAssertGreaterThan(EventParticipationStatus.tentative.appleCalendarBackgroundAlpha, EventParticipationStatus.declined.appleCalendarBackgroundAlpha)
    }
    func testMeetingBrowserKindMetadataIsStable() {
        XCTAssertEqual(
            MeetingBrowserKind.allCases.map(\.rawValue),
            [
                "chrome",
                "edge",
                "brave",
                "vivaldi",
                "chromium",
                "safari",
                "firefox",
                "firefoxDeveloperEdition",
                "librewolf",
                "floorp",
                "zen",
                "arc",
                "opera",
                "duckDuckGo",
                "orion",
            ]
        )
        XCTAssertEqual(MeetingBrowserKind.safari.title, "Safari")
        XCTAssertEqual(MeetingBrowserKind.chrome.title, "Chrome")
        XCTAssertEqual(MeetingBrowserKind.edge.title, "Microsoft Edge")
        XCTAssertEqual(MeetingBrowserKind.firefox.title, "Firefox")
        XCTAssertEqual(MeetingBrowserKind.chrome.bundleIdentifier, "com.google.Chrome")
        XCTAssertEqual(MeetingBrowserKind.edge.bundleIdentifier, "com.microsoft.edgemac")
        XCTAssertEqual(MeetingBrowserKind.firefox.bundleIdentifier, "org.mozilla.firefox")
    }
    func testFootballCalendarAlertOptionMetadataIsStable() {
        XCTAssertEqual(
            FootballCalendarAlertOption.allCases.map(\.rawValue),
            [
                "none",
                "atTimeOfEvent",
                "fiveMinutesBefore",
                "tenMinutesBefore",
                "fifteenMinutesBefore",
                "thirtyMinutesBefore",
                "oneHourBefore",
                "twoHoursBefore",
                "oneDayBefore",
                "twoDaysBefore",
            ]
        )
        XCTAssertEqual(FootballCalendarAlertOption.none.title, "None")
        XCTAssertEqual(FootballCalendarAlertOption.atTimeOfEvent.title, "At time of event")
        XCTAssertEqual(FootballCalendarAlertOption.twoDaysBefore.relativeOffset(), -2 * 24 * 60 * 60)
    }
    func testFootballCompetitionPresetsSplitBetweenClubAndNationalTeamBuckets() {
        let grouped = Dictionary(grouping: FootballCompetitionPreset.menuPresets, by: \.category)

        XCTAssertTrue(grouped[.clubCompetitions]?.contains(where: { $0.slug == "eng.1" }) == true)
        XCTAssertTrue(grouped[.nationalTeams]?.contains(where: { $0.slug == "fifa.world" }) == true)
        XCTAssertEqual(FootballCompetitionCategory.clubCompetitions.title, "Club Competitions")
        XCTAssertEqual(FootballCompetitionCategory.nationalTeams.title, "National Teams")
        XCTAssertEqual(FootballCompetitionPreset.category(forCompetitionSlug: "fifa.world"), .nationalTeams)
        XCTAssertEqual(FootballCompetitionPreset.category(forCompetitionSlug: "eng.1"), .clubCompetitions)
    }
    func testFootballCompetitionPresetsExposeRegionalBuckets() {
        let grouped = Dictionary(grouping: FootballCompetitionPreset.menuPresets, by: \.region)

        XCTAssertEqual(FootballCompetitionRegion.allCases, [.northAmerica, .southAmerica, .europe, .global])
        XCTAssertEqual(FootballCompetitionRegion.northAmerica.title, "North America")
        XCTAssertEqual(FootballCompetitionRegion.southAmerica.title, "South America")
        XCTAssertEqual(FootballCompetitionRegion.europe.title, "Europe")
        XCTAssertEqual(FootballCompetitionRegion.global.title, "Global")

        XCTAssertTrue(grouped[.northAmerica]?.contains(where: { $0.slug == "mex.1" }) == true)
        XCTAssertTrue(grouped[.southAmerica]?.contains(where: { $0.slug == "conmebol.libertadores" }) == true)
        XCTAssertTrue(grouped[.europe]?.contains(where: { $0.slug == "uefa.champions" }) == true)
        XCTAssertTrue(grouped[.global]?.contains(where: { $0.slug == "fifa.world" }) == true)

        XCTAssertEqual(FootballCompetitionPreset.region(forCompetitionSlug: "mex.1"), .northAmerica)
        XCTAssertEqual(FootballCompetitionPreset.region(forCompetitionSlug: "conmebol.america"), .southAmerica)
        XCTAssertEqual(FootballCompetitionPreset.region(forCompetitionSlug: "esp.1"), .europe)
        XCTAssertEqual(FootballCompetitionPreset.region(forCompetitionSlug: "fifa.world"), .global)
    }
    func testCalendarColorPaletteOptionsHaveUniqueIDsAndKnownFallback() {
        let options = CalendarColorPalette.options
        let uniqueIDs = Set(options.map(\.id))

        XCTAssertEqual(options.count, 12)
        XCTAssertEqual(uniqueIDs.count, options.count)

        let mint = CalendarColorPalette.color(for: "mint")
        let expectedMint = options.first(where: { $0.id == "mint" })!.color
        XCTAssertEqual(mint, expectedMint)

        let fallback = CalendarColorPalette.color(for: "does-not-exist")
        let expectedFallback = options.first(where: { $0.id == "blue" })!.color
        XCTAssertEqual(fallback, expectedFallback)
    }
    func testDefaultsKeysAreUniqueAndComplete() {
        let keys = [
            DefaultsKeys.includeEvents,
            DefaultsKeys.includeAllDayEvents,
            DefaultsKeys.includeReminders,
            DefaultsKeys.includeAstronomy,
            DefaultsKeys.includeSunriseSunset,
            DefaultsKeys.includeSolarNoonMidnight,
            DefaultsKeys.includeMoonPhases,
            DefaultsKeys.includeOrbitalHighlights,
            DefaultsKeys.useAutomaticAstronomyLocation,
            DefaultsKeys.astronomyColorID,
            DefaultsKeys.astronomyLatitude,
            DefaultsKeys.astronomyLongitude,
            DefaultsKeys.selectedEventCalendarIDs,
            DefaultsKeys.selectedReminderCalendarIDs,
            DefaultsKeys.weekdayOnlyEventCalendarIDs,
            DefaultsKeys.weekdayOnlyReminderCalendarIDs,
            DefaultsKeys.nonWorkingDateKeys,
            DefaultsKeys.lookAheadHours,
            DefaultsKeys.contextualPreviewLeadMinutes,
            DefaultsKeys.menuBarRotationWindowMinutes,
            DefaultsKeys.alertLeadMinutes,
            DefaultsKeys.concurrentEventRotationSeconds,
            DefaultsKeys.useSimplifiedCountdown,
            DefaultsKeys.activeEventDisplayMode,
            DefaultsKeys.useEventTitleEllipsis,
            DefaultsKeys.eventTitleMaxCharacters,
            DefaultsKeys.maxListItems,
            DefaultsKeys.enableBlinkAlert,
            DefaultsKeys.menuBarFontSize,
            DefaultsKeys.skippedItemKeys,
            DefaultsKeys.footballTargetCalendarID,
            DefaultsKeys.footballAutoAddCompetitionSlugs,
            DefaultsKeys.footballCalendarAlertOption,
            DefaultsKeys.enableFootballAutoAddNotifications,
            DefaultsKeys.showFinishedFootballMatches,
            DefaultsKeys.finishedFootballMatchLookbackDays,
            DefaultsKeys.footballMatchLookaheadDays,
            DefaultsKeys.meetingBrowserRouting,
            DefaultsKeys.managedFootballEventRecords,
        ]

        XCTAssertEqual(keys.count, 39)
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertTrue(keys.contains("activeEventDisplayMode"))
        XCTAssertTrue(keys.contains("contextualPreviewLeadMinutes"))
        XCTAssertTrue(keys.contains("menuBarRotationWindowMinutes"))
        XCTAssertTrue(keys.contains("menuBarFontSize"))
        XCTAssertTrue(keys.contains("meetingBrowserRouting"))
        XCTAssertTrue(keys.contains("nonWorkingDateKeys"))
        XCTAssertTrue(keys.contains("footballAutoAddCompetitionSlugs"))
        XCTAssertTrue(keys.contains("enableFootballAutoAddNotifications"))
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
            calendarColor: AlertCalendarColor(red: 0.20, green: 0.50, blue: 0.90),
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
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
            calendarColor: AlertCalendarColor(red: 0.20, green: 0.50, blue: 0.90),
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
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
            calendarColor: AlertCalendarColor(red: 0.20, green: 0.50, blue: 0.90),
            kind: .reminder,
            footballMatch: nil,
            footballMenuBarDisplay: nil
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
            calendarColor: AlertCalendarColor(red: 0.20, green: 0.50, blue: 0.90),
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
        let tentative = UpcomingItem(
            id: "item-1",
            title: "Planning",
            date: start,
            endDate: start.addingTimeInterval(1800),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: 12,
            locationText: "Room 4",
            meetingURL: meetingURL,
            eventParticipationStatus: .tentative,
            calendarID: "cal-1",
            calendarName: "Work",
            calendarColor: AlertCalendarColor(red: 0.20, green: 0.50, blue: 0.90),
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
        let recurring = UpcomingItem(
            id: "item-1",
            title: "Planning",
            date: start,
            endDate: start.addingTimeInterval(1800),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: 12,
            locationText: "Room 4",
            meetingURL: meetingURL,
            isRecurring: true,
            calendarID: "cal-1",
            calendarName: "Work",
            calendarColor: AlertCalendarColor(red: 0.20, green: 0.50, blue: 0.90),
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
        let withDocument = UpcomingItem(
            id: "item-1",
            title: "Planning",
            date: start,
            endDate: start.addingTimeInterval(1800),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: 12,
            locationText: "Room 4",
            meetingURL: meetingURL,
            hasDocumentIndicator: true,
            calendarID: "cal-1",
            calendarName: "Work",
            calendarColor: AlertCalendarColor(red: 0.20, green: 0.50, blue: 0.90),
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )

        XCTAssertEqual(base, same)
        XCTAssertNotEqual(base, differentKind)
        XCTAssertNotEqual(base, withoutMeetingURL)
        XCTAssertNotEqual(base, tentative)
        XCTAssertNotEqual(base, recurring)
        XCTAssertNotEqual(base, withDocument)
    }
    func testMenuMarkerStyleDistinguishesSymbolFamilies() {
        XCTAssertEqual(MenuMarkerStyle.allDay(.systemBlue), MenuMarkerStyle.allDay(.systemBlue))
        XCTAssertNotEqual(MenuMarkerStyle.color(.systemBlue), MenuMarkerStyle.reminder(.systemBlue))
        XCTAssertNotEqual(MenuMarkerStyle.birthday(.systemPink), MenuMarkerStyle.allDay(.systemPink))
        XCTAssertNotEqual(MenuMarkerStyle.travel(.systemPink), MenuMarkerStyle.allDay(.systemPink))
        XCTAssertNotEqual(MenuMarkerStyle.newMoon, MenuMarkerStyle.fullMoon)
        XCTAssertNotEqual(MenuMarkerStyle.juneSolstice, MenuMarkerStyle.aphelion)
    }
    func testAstronomyMomentsExposeCompleteMetadata() {
        XCTAssertEqual(AstronomyMoment.allCases.count, 18)
        XCTAssertEqual(Set(AstronomyMoment.allCases.map(\.title)).count, 18)
        XCTAssertTrue(AstronomyMoment.allCases.allSatisfy { !$0.fallbackSymbolName.isEmpty })
        XCTAssertEqual(AstronomyMoment.allCases.filter { $0.svgAssetName != nil }.count, 10)
        XCTAssertEqual(
            Set(AstronomyMoment.solarMoments + AstronomyMoment.lunarPhases + AstronomyMoment.orbitalHighlights),
            Set(AstronomyMoment.allCases)
        )
    }}
