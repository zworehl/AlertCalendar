import AppKit
import Foundation
import XCTest
@testable import AlertCalendar

final class MenuBarStateTests: XCTestCase {
    func testMenuBarRotationExcludesNextDayAllDayEventOutsideRotationWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 23, hour: 10, minute: 0))!
        let startDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 24, hour: 0, minute: 0))!
        let endDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 0, minute: 0))!
        let futureWindowEnd = now.addingTimeInterval(8 * 60 * 60)

        XCTAssertFalse(
            CalendarMonitor.shouldIncludeAllDayItemInMenuBarRotation(
                startDate: startDay,
                endDate: endDay,
                now: now,
                futureWindowEnd: futureWindowEnd,
                calendar: calendar
            )
        )
    }

    func testMenuBarRotationKeepsCurrentDayAllDayEventVisible() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 23, hour: 10, minute: 0))!
        let startDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 23, hour: 0, minute: 0))!
        let endDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 24, hour: 0, minute: 0))!
        let futureWindowEnd = now.addingTimeInterval(8 * 60 * 60)

        XCTAssertTrue(
            CalendarMonitor.shouldIncludeAllDayItemInMenuBarRotation(
                startDate: startDay,
                endDate: endDay,
                now: now,
                futureWindowEnd: futureWindowEnd,
                calendar: calendar
            )
        )
    }

    func testMenuBarEmptyStateTextUsesRotationWindowWhenLaterItemsExist() {
        XCTAssertEqual(
            CalendarMonitor.menuBarEmptyStateText(
                menuBarRotationWindowMinutes: 60,
                hasLaterItemsInDropdownWindow: true
            ),
            "No items in next 1h"
        )
    }

    func testMenuBarEmptyStateTextFallsBackToGenericEmptyStateWhenNothingElseExists() {
        XCTAssertEqual(
            CalendarMonitor.menuBarEmptyStateText(
                menuBarRotationWindowMinutes: 60,
                hasLaterItemsInDropdownWindow: false
            ),
            "No upcoming items"
        )
    }

    func testMenuBarRotationWindowDescriptionFormatsCompoundDurations() {
        XCTAssertEqual(
            CalendarMonitor.menuBarRotationWindowDescription(minutes: 90),
            "1h 30m"
        )
    }

    func testMenuBarAccessorySymbolsShowDocumentBeforeRecurrence() throws {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let event = UpcomingItem(
            id: "event-1",
            title: "Design review",
            date: startDate,
            endDate: startDate.addingTimeInterval(30 * 60),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: try XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij")),
            isRecurring: true,
            hasDocumentIndicator: true,
            calendarID: "calendar-1",
            calendarName: "Work",
            calendarColor: .systemBlue,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )

        XCTAssertEqual(
            CalendarMonitor.menuBarAccessorySymbolNames(for: event),
            ["paperclip", "repeat"]
        )
    }

    @MainActor
    func testRecurringSymbolImageKeepsTransparentCanvasCorners() throws {
        let image = try XCTUnwrap(
            MenuSymbolImageProvider.tintedSystemSymbol(
                named: "repeat",
                pointSize: 12,
                weight: .semibold,
                tintColor: .white
            )
        )
        let representation = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let cornerColor = try XCTUnwrap(representation.colorAt(x: 0, y: 0))

        XCTAssertEqual(cornerColor.alphaComponent, 0, accuracy: 0.001)
    }

    @MainActor
    func testGameStoreMarkersMatchAllDayMarkerSizes() {
        XCTAssertEqual(MenuMarkerMetrics.symbolSize, 12)
        XCTAssertEqual(
            MenuBarStatusLabel.markerWidthForStyle(
                .gameStore(.steam),
                defaultWidth: 3,
                imageWidth: MenuMarkerMetrics.symbolSize
            ),
            MenuMarkerMetrics.symbolSize
        )
        XCTAssertEqual(
            MenuBarStatusLabel.markerWidthForStyle(
                .allDay(.systemBlue),
                defaultWidth: 3,
                imageWidth: MenuMarkerMetrics.symbolSize
            ),
            MenuMarkerMetrics.symbolSize
        )
        XCTAssertEqual(
            MenuBarStatusLabel.markerWidthForStyle(
                .sunset,
                defaultWidth: 3,
                imageWidth: MenuMarkerMetrics.symbolSize
            ),
            MenuMarkerMetrics.symbolSize
        )

        for store in GameStore.allCases {
            XCTAssertNotNil(GameStoreSymbolProvider.assetURL(for: store))
            XCTAssertEqual(
                GameStoreSymbolProvider.image(for: store, size: MenuMarkerMetrics.symbolSize)?.size,
                NSSize(width: MenuMarkerMetrics.symbolSize, height: MenuMarkerMetrics.symbolSize)
            )
        }
    }

    func testGameStoreDropdownMarkersUseOpticalVerticalOffsets() {
        XCTAssertEqual(MenuContentView.gameStoreMarkerTopPadding(for: .steam), 1)
        XCTAssertEqual(
            MenuContentView.gameStoreMarkerTopPadding(for: .nintendoSwitch),
            MenuMarkerMetrics.markerFirstLineTopPadding
        )

        for store in [GameStore.xbox, .playStation] {
            XCTAssertEqual(MenuContentView.gameStoreMarkerTopPadding(for: store), 0)
        }
    }

    func testDropdownMarkerAndDetailTextCenterOnTheFirstTitleLine() {
        XCTAssertEqual(
            MenuMarkerMetrics.markerFirstLineTopPadding + (MenuMarkerMetrics.symbolSize / 2),
            MenuMarkerMetrics.rowTitleLineHeight / 2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MenuMarkerMetrics.detailFirstLineTopPadding + (MenuMarkerMetrics.rowDetailLineHeight / 2),
            MenuMarkerMetrics.rowTitleLineHeight / 2,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(MenuMarkerMetrics.rowContentTopPadding, 0)
        XCTAssertEqual(
            MenuMarkerMetrics.rowContentTopPadding,
            MenuMarkerMetrics.rowContentBottomPadding
        )
        XCTAssertGreaterThanOrEqual(
            MenuMarkerMetrics.rowContentTopPadding + MenuMarkerMetrics.rowContentBottomPadding,
            8
        )
    }

    @MainActor
    func testInactiveSegmentsHaveNoOuterHorizontalPadding() {
        XCTAssertEqual(
            MenuBarStatusLabel.outerHorizontalPadding(
                hasBackground: false,
                defaultPadding: 5
            ),
            0
        )
    }

    @MainActor
    func testActiveSegmentsKeepOuterHorizontalPadding() {
        XCTAssertEqual(
            MenuBarStatusLabel.outerHorizontalPadding(
                hasBackground: true,
                defaultPadding: 5
            ),
            5
        )
    }

    func testDocumentIndicatorOnlyUsesDocumentURLs() throws {
        let meetingURL = try XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij"))

        XCTAssertTrue(
            CalendarMonitor.hasDocumentIndicator(
                eventURL: try XCTUnwrap(URL(string: "https://example.com/agenda.pdf")),
                notes: nil,
                meetingURL: nil
            )
        )
        XCTAssertTrue(
            CalendarMonitor.hasDocumentIndicator(
                eventURL: nil,
                notes: "Prep: https://docs.google.com/document/d/doc-id/edit",
                meetingURL: nil
            )
        )
        XCTAssertFalse(
            CalendarMonitor.hasDocumentIndicator(
                eventURL: try XCTUnwrap(URL(string: "https://example.com/agenda")),
                notes: nil,
                meetingURL: nil
            )
        )
        XCTAssertFalse(
            CalendarMonitor.hasDocumentIndicator(
                eventURL: nil,
                notes: "Agenda and prep notes",
                meetingURL: nil
            )
        )
        XCTAssertFalse(
            CalendarMonitor.hasDocumentIndicator(
                eventURL: meetingURL,
                notes: "Join the call at https://meet.google.com/abc-defg-hij",
                meetingURL: meetingURL
            )
        )
        XCTAssertFalse(
            CalendarMonitor.hasDocumentIndicator(
                eventURL: try XCTUnwrap(URL(string: "alertcalendar-football://fixture?matchID=1&competition=crc.1")),
                notes: nil,
                meetingURL: nil
            )
        )
    }

    func testDropdownAccessorySymbolsHideWhileHovered() {
        let symbolNames = ["paperclip", "repeat"]

        XCTAssertEqual(
            MenuContentView.dropdownAccessorySymbolNames(symbolNames, isHovered: false),
            symbolNames
        )
        XCTAssertEqual(
            MenuContentView.dropdownAccessorySymbolNames(symbolNames, isHovered: true),
            []
        )
        XCTAssertEqual(MenuContentView.dropdownAccessorySymbolsTrailingReservation([]), 0)
        XCTAssertEqual(
            MenuContentView.dropdownAccessorySymbolsTrailingReservation(["repeat"]),
            8 + MenuMarkerMetrics.symbolSize
        )
        XCTAssertEqual(
            MenuContentView.dropdownAccessorySymbolsTrailingReservation(symbolNames),
            12 + (MenuMarkerMetrics.symbolSize * 2)
        )
    }

    func testDropdownUsesNativeMacOSControlAndTypographyMetrics() {
        XCTAssertGreaterThanOrEqual(MenuContentNativeMetrics.toolbarButtonSize, 28)
        XCTAssertEqual(MenuMarkerMetrics.rowTitleSize, NSFont.systemFontSize)
        XCTAssertEqual(
            MenuMarkerMetrics.rowDetailSize,
            NSFont.systemFontSize(for: .small)
        )
        XCTAssertLessThan(MenuMarkerMetrics.compactMetadataSize, MenuMarkerMetrics.rowDetailSize)
    }

    func testMenuBarAccessorySymbolsShowRecurrenceForReminders() {
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        let reminder = UpcomingItem(
            id: "reminder-1",
            title: "Submit report",
            date: dueDate,
            endDate: nil,
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            isRecurring: true,
            calendarID: "reminders-1",
            calendarName: "Reminders",
            calendarColor: .systemOrange,
            kind: .reminder,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )

        XCTAssertEqual(
            CalendarMonitor.menuBarAccessorySymbolNames(for: reminder),
            ["repeat"]
        )
    }

    func testMenuBarAccessorySymbolsCanHideDocumentAndRecurrenceForBirthdays() throws {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let event = UpcomingItem(
            id: "birthday-1",
            title: "Birthday",
            date: startDate,
            endDate: startDate.addingTimeInterval(24 * 60 * 60),
            isAllDay: true,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            isRecurring: true,
            hasDocumentIndicator: true,
            calendarID: "birthdays",
            calendarName: "Birthdays",
            calendarColor: .systemPink,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )

        XCTAssertEqual(
            CalendarMonitor.menuBarAccessorySymbolNames(
                for: event,
                includesDocumentIndicator: false,
                includesRecurrenceIndicator: false
            ),
            []
        )
    }

    func testDocumentIndicatorURLDetectsDocumentsButIgnoresMeetingLinks() throws {
        XCTAssertTrue(
            CalendarMonitor.isDocumentIndicatorURL(
                try XCTUnwrap(URL(string: "https://example.com/agenda.pdf"))
            )
        )
        XCTAssertTrue(
            CalendarMonitor.isDocumentIndicatorURL(
                try XCTUnwrap(URL(string: "https://docs.google.com/document/d/doc-id/edit"))
            )
        )
        XCTAssertTrue(
            CalendarMonitor.isDocumentIndicatorURL(
                try XCTUnwrap(URL(string: "https://docs.google.com/spreadsheets/d/sheet-id/edit"))
            )
        )
        XCTAssertTrue(
            CalendarMonitor.isDocumentIndicatorURL(
                try XCTUnwrap(URL(string: "https://docs.google.com/presentation/d/deck-id/edit"))
            )
        )
        XCTAssertFalse(
            CalendarMonitor.isDocumentIndicatorURL(
                try XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij"))
            )
        )
    }

    func testAlertBlinkUpdatesOncePerSecond() {
        XCTAssertEqual(CalendarMonitorCadence.menuBarAnimationInterval, 1)
        XCTAssertEqual(CalendarMonitor.alertBlinkPeriod, 2)
    }

    func testAlertBlinkTextOpacityUsesPeriodicWave() {
        XCTAssertEqual(
            CalendarMonitor.alertBlinkTextOpacity(now: Date(timeIntervalSinceReferenceDate: 0)),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            CalendarMonitor.alertBlinkTextOpacity(
                now: Date(timeIntervalSinceReferenceDate: CalendarMonitor.alertBlinkPeriod / 2)
            ),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            CalendarMonitor.alertBlinkTextOpacity(
                now: Date(timeIntervalSinceReferenceDate: CalendarMonitor.alertBlinkPeriod)
            ),
            1,
            accuracy: 0.001
        )
    }

    func testAlertBlinkTextOpacityTransitionsWithinPeriod() {
        let peak = CalendarMonitor.alertBlinkTextOpacity(now: Date(timeIntervalSinceReferenceDate: 0))
        let falling = CalendarMonitor.alertBlinkTextOpacity(
            now: Date(timeIntervalSinceReferenceDate: CalendarMonitor.alertBlinkPeriod / 4)
        )
        let trough = CalendarMonitor.alertBlinkTextOpacity(
            now: Date(timeIntervalSinceReferenceDate: CalendarMonitor.alertBlinkPeriod / 2)
        )

        XCTAssertGreaterThan(peak, falling)
        XCTAssertGreaterThan(falling, trough)
    }

    func testTimedEventsStopBlinkingAtTheirStart() {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let event = makeTimedEvent(
            title: "Design review",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(30 * 60),
            meetingURL: nil
        )

        XCTAssertTrue(
            CalendarMonitor.shouldBlinkForItem(
                event,
                now: startDate.addingTimeInterval(-1),
                settings: .defaults
            )
        )
        XCTAssertFalse(CalendarMonitor.shouldBlinkForItem(event, now: startDate, settings: .defaults))
        XCTAssertFalse(
            CalendarMonitor.shouldBlinkForItem(
                event,
                now: startDate.addingTimeInterval(1),
                settings: .defaults
            )
        )
    }

    func testStartedAllDayEventsAndOverdueRemindersDoNotBlink() {
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        let allDayEvent = makeTimedEvent(
            title: "Birthday",
            startDate: dueDate,
            endDate: dueDate.addingTimeInterval(24 * 60 * 60),
            isAllDay: true,
            meetingURL: nil
        )
        let reminder = makeReminder(title: "Submit report", dueDate: dueDate)
        let now = dueDate.addingTimeInterval(60)

        XCTAssertFalse(CalendarMonitor.shouldBlinkForItem(allDayEvent, now: now, settings: .defaults))
        XCTAssertFalse(CalendarMonitor.shouldBlinkForItem(reminder, now: now, settings: .defaults))
    }

    func testTimedEventNowSegmentShowsForFirstMinuteAfterStartWithoutMeetingURL() {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let event = makeTimedEvent(
            title: "Design review",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(30 * 60),
            meetingURL: nil
        )

        XCTAssertEqual(
            CalendarMonitor.timedEventNowMenuSegment(
                for: event,
                compactTitle: "Design review",
                now: startDate
            ),
            "Design review now"
        )
        XCTAssertEqual(
            CalendarMonitor.timedEventNowMenuSegment(
                for: event,
                compactTitle: "Design review",
                now: startDate.addingTimeInterval(59)
            ),
            "Design review now"
        )
    }

    func testTimedEventNowSegmentStopsAfterOneMinute() throws {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let meeting = makeTimedEvent(
            title: "Design review",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(30 * 60),
            meetingURL: try XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij"))
        )

        XCTAssertNil(
            CalendarMonitor.timedEventNowMenuSegment(
                for: meeting,
                compactTitle: "Design review",
                now: startDate.addingTimeInterval(60)
            )
        )
    }

    func testTimedEventNowStateIgnoresAllDayEvents() {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let allDayEvent = makeTimedEvent(
            title: "Design review",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(30 * 60),
            isAllDay: true,
            meetingURL: nil
        )

        XCTAssertFalse(
            CalendarMonitor.shouldShowTimedEventNowState(
                for: allDayEvent,
                now: startDate.addingTimeInterval(30)
            )
        )
    }

    func testTravelDepartureMenuSegmentCountsDownToLeaveTime() {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let event = makeTimedEvent(
            title: "Dentist",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(30 * 60),
            travelTimeMinutes: 25,
            meetingURL: nil
        )

        XCTAssertEqual(
            CalendarMonitor.travelDepartureMenuSegment(
                for: event,
                compactTitle: "Dentist",
                now: startDate.addingTimeInterval(-30 * 60),
                simplified: false
            ),
            "Dentist leave in 5m"
        )
    }

    func testTravelDepartureMenuSegmentShowsLeaveNowBeforeEventStart() {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let event = makeTimedEvent(
            title: "Dentist",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(30 * 60),
            travelTimeMinutes: 25,
            meetingURL: nil
        )

        XCTAssertEqual(
            CalendarMonitor.travelDepartureMenuSegment(
                for: event,
                compactTitle: "Dentist",
                now: startDate.addingTimeInterval(-10 * 60),
                simplified: false
            ),
            "Leave now for Dentist"
        )
    }

    func testTravelDepartureProgressTracksTravelWindow() {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let event = makeTimedEvent(
            title: "Dentist",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(30 * 60),
            travelTimeMinutes: 20,
            meetingURL: nil
        )

        XCTAssertNil(
            CalendarMonitor.travelDepartureProgress(
                for: event,
                now: startDate.addingTimeInterval(-25 * 60)
            )
        )
        let midpointProgress = CalendarMonitor.travelDepartureProgress(
            for: event,
            now: startDate.addingTimeInterval(-10 * 60)
        )
        XCTAssertEqual(midpointProgress ?? -1, 0.5, accuracy: 0.001)
        XCTAssertNil(CalendarMonitor.travelDepartureProgress(for: event, now: startDate))
    }

    func testTravelDepartureStateIgnoresVirtualMeetings() throws {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let event = makeTimedEvent(
            title: "Design review",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(30 * 60),
            travelTimeMinutes: 25,
            meetingURL: try XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij"))
        )

        XCTAssertNil(CalendarMonitor.travelStartDate(for: event))
        XCTAssertFalse(
            CalendarMonitor.shouldShowTravelDepartureState(
                for: event,
                now: startDate.addingTimeInterval(-10 * 60)
            )
        )
    }

    func testOverdueReminderProgressIsFull() {
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        let reminder = makeReminder(
            title: "Submit expenses",
            dueDate: dueDate
        )

        XCTAssertNil(
            CalendarMonitor.activeItemProgress(
                for: reminder,
                now: dueDate.addingTimeInterval(-60)
            )
        )
        XCTAssertEqual(
            CalendarMonitor.activeItemProgress(
                for: reminder,
                now: dueDate
            ),
            1
        )
        XCTAssertEqual(
            CalendarMonitor.activeItemProgress(
                for: reminder,
                now: dueDate.addingTimeInterval(60)
            ),
            1
        )
    }

    func testParticipationTextureStatusIncludesTentativeAndPendingEvents() {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let endDate = startDate.addingTimeInterval(30 * 60)
        let tentativeEvent = makeTimedEvent(
            title: "Tentative design review",
            startDate: startDate,
            endDate: endDate,
            travelTimeMinutes: 20,
            meetingURL: nil,
            showsMutedBackground: true,
            participationStatus: .tentative
        )
        let pendingEvent = makeTimedEvent(
            title: "Pending design review",
            startDate: startDate,
            endDate: endDate,
            meetingURL: nil,
            showsMutedBackground: true,
            participationStatus: .pending
        )
        let acceptedEvent = makeTimedEvent(
            title: "Accepted design review",
            startDate: startDate,
            endDate: endDate,
            meetingURL: nil,
            participationStatus: .accepted
        )

        XCTAssertEqual(
            CalendarMonitor.participationTextureStatus(for: tentativeEvent),
            .tentative
        )
        XCTAssertEqual(
            CalendarMonitor.participationTextureStatus(for: pendingEvent),
            .pending
        )
        XCTAssertNil(CalendarMonitor.participationTextureStatus(for: acceptedEvent))
    }

    func testActiveEventProgressUsesActualElapsedTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 9))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 9))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 6))!
        let event = makeTimedEvent(
            title: "Design review",
            startDate: startDate,
            endDate: endDate,
            meetingURL: nil
        )

        XCTAssertEqual(
            CalendarMonitor.activeItemProgress(
                for: event,
                now: now
            ) ?? -1,
            0.9375,
            accuracy: 0.001
        )
    }

    func testAlertForItemIncludesAnyTimedEventFirstMinute() throws {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let event = makeTimedEvent(
            title: "Design review",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(30 * 60),
            meetingURL: nil
        )
        let now = startDate.addingTimeInterval(30)

        XCTAssertTrue(
            CalendarMonitor.shouldAlertForItem(
                event,
                now: now,
                leadSeconds: 5 * 60
            )
        )
        XCTAssertEqual(
            CalendarMonitor.alertDescription(for: event, now: now),
            "Design review starts now."
        )
    }

    func testReminderAlertDescriptionUsesDueLanguage() {
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        let reminder = makeReminder(title: "Submit expenses", dueDate: dueDate)

        XCTAssertEqual(
            CalendarMonitor.alertDescription(
                for: reminder,
                now: dueDate.addingTimeInterval(-4 * 60)
            ),
            "Submit expenses — due in 4 minutes."
        )
        XCTAssertEqual(
            CalendarMonitor.alertDescription(
                for: reminder,
                now: dueDate.addingTimeInterval(-45)
            ),
            "Submit expenses — due in 45s."
        )
    }

    func testFootballMenuBarDetailsShowWhenMatchHasNoConcurrentEvent() {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let match = FootballTestData.friendlyMatch(
            id: "match-1",
            startDate: startDate,
            statusState: .scheduled
        )
        let footballItem = makeFootballMenuBarItem(match)
        let laterEvent = makeTimedEvent(
            id: "later-event",
            title: "Later review",
            startDate: startDate.addingTimeInterval(2 * 60 * 60),
            endDate: startDate.addingTimeInterval(3 * 60 * 60),
            meetingURL: nil
        )

        XCTAssertTrue(
            CalendarMonitor.shouldShowFootballMenuBarDetails(
                for: footballItem,
                in: [footballItem, laterEvent]
            )
        )
    }

    func testFootballMenuBarDetailsShowWhenCalendarEventOverlapsMatch() {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let match = FootballTestData.friendlyMatch(
            id: "match-1",
            startDate: startDate,
            statusState: .scheduled
        )
        let footballItem = makeFootballMenuBarItem(match)
        let overlappingEvent = makeTimedEvent(
            id: "overlapping-event",
            title: "Design review",
            startDate: startDate.addingTimeInterval(30 * 60),
            endDate: startDate.addingTimeInterval(60 * 60),
            meetingURL: nil
        )

        XCTAssertTrue(
            CalendarMonitor.shouldShowFootballMenuBarDetails(
                for: footballItem,
                in: [footballItem, overlappingEvent]
            )
        )
    }

    func testFootballMenuBarDetailsShowWhenAnotherMatchOverlaps() {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let firstMatch = FootballTestData.friendlyMatch(
            id: "match-1",
            startDate: startDate,
            statusState: .scheduled
        )
        let secondMatch = FootballTestData.friendlyMatch(
            id: "match-2",
            startDate: startDate.addingTimeInterval(45 * 60),
            statusState: .scheduled
        )
        let firstFootballItem = makeFootballMenuBarItem(firstMatch)
        let secondFootballItem = makeFootballMenuBarItem(secondMatch)

        XCTAssertTrue(
            CalendarMonitor.shouldShowFootballMenuBarDetails(
                for: firstFootballItem,
                in: [firstFootballItem, secondFootballItem]
            )
        )
    }

    func testFootballMenuBarStatusKeepsLiveMinuteWhenDetailsShowForOverlap() {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let now = startDate.addingTimeInterval(88 * 60)
        let match = FootballTestData.friendlyMatch(
            id: "match-1",
            startDate: startDate,
            statusState: .inProgress,
            statusText: "88'",
            homeScore: "2",
            awayScore: "1"
        )
        let footballItem = makeFootballMenuBarItem(match)
        let overlappingEvent = makeTimedEvent(
            id: "overlapping-event",
            title: "Design review",
            startDate: startDate.addingTimeInterval(30 * 60),
            endDate: startDate.addingTimeInterval(90 * 60),
            meetingURL: nil
        )

        XCTAssertTrue(
            CalendarMonitor.shouldShowFootballMenuBarDetails(
                for: footballItem,
                in: [footballItem, overlappingEvent]
            )
        )
        XCTAssertTrue(CalendarMonitor.shouldShowFootballMenuBarStatus(for: footballItem))
        XCTAssertEqual(
            CalendarMonitor.resolvedFootballMenuBarStatusText(for: match, now: now),
            "88'"
        )
    }

    func testFootballMenuBarStatusTextOmitsExtraTimePrefixWhenMinuteAlreadyShowsIt() {
        XCTAssertEqual(CalendarMonitor.compactFootballMenuBarStatusText("ET 105'"), "105'")
        XCTAssertEqual(CalendarMonitor.compactFootballMenuBarStatusText("ET 120'+2'"), "120'+2'")
        XCTAssertEqual(CalendarMonitor.compactFootballMenuBarStatusText("ET"), "ET")
        XCTAssertEqual(CalendarMonitor.compactFootballMenuBarStatusText("ET 90'+2'"), "ET 90'+2'")
    }

    private func makeTimedEvent(
        id: String = "event-1",
        title: String,
        startDate: Date,
        endDate: Date?,
        isAllDay: Bool = false,
        travelTimeMinutes: Int? = nil,
        meetingURL: URL?,
        showsMutedBackground: Bool = false,
        participationStatus: EventParticipationStatus? = nil
    ) -> UpcomingItem {
        UpcomingItem(
            id: id,
            title: title,
            date: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            showsMutedBackground: showsMutedBackground,
            travelTimeMinutes: travelTimeMinutes,
            locationText: nil,
            meetingURL: meetingURL,
            eventParticipationStatus: participationStatus,
            calendarID: "calendar-1",
            calendarName: "Work",
            calendarColor: .systemBlue,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
    }

    private func makeFootballMenuBarItem(_ match: FootballFixtureMatch) -> UpcomingItem {
        UpcomingItem(
            id: match.id,
            title: FootballFixtureFormatter.calendarTitle(for: match),
            date: match.startDate,
            endDate: match.startDate.addingTimeInterval(2 * 60 * 60),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: match.locationText,
            meetingURL: nil,
            calendarID: "football-calendar",
            calendarName: "Football",
            calendarColor: .systemOrange,
            kind: .event,
            footballMatch: match,
            footballMenuBarDisplay: FootballFixtureFormatter.menuBarDisplay(
                for: match,
                competitionLocalLogoURL: nil,
                homeLocalLogoURL: nil,
                awayLocalLogoURL: nil
            )
        )
    }

    private func makeReminder(
        id: String = "reminder-1",
        title: String,
        dueDate: Date
    ) -> UpcomingItem {
        UpcomingItem(
            id: id,
            title: title,
            date: dueDate,
            endDate: nil,
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: "reminders-1",
            calendarName: "Tasks",
            calendarColor: .systemOrange,
            kind: .reminder,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
    }
}
