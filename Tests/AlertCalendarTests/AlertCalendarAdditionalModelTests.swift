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
            DefaultsKeys.footballCalendarAlertOption,
            DefaultsKeys.showFinishedFootballMatches,
            DefaultsKeys.managedFootballEventRecords,
        ]

        XCTAssertEqual(keys.count, 33)
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertTrue(keys.contains("activeEventDisplayMode"))
        XCTAssertTrue(keys.contains("contextualPreviewLeadMinutes"))
        XCTAssertTrue(keys.contains("menuBarRotationWindowMinutes"))
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
            calendarColor: NSColor(calibratedRed: 0.20, green: 0.50, blue: 0.90, alpha: 1),
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
            calendarColor: NSColor(calibratedRed: 0.20, green: 0.50, blue: 0.90, alpha: 1),
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
            calendarColor: NSColor(calibratedRed: 0.20, green: 0.50, blue: 0.90, alpha: 1),
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )

        XCTAssertEqual(base, same)
        XCTAssertNotEqual(base, differentKind)
        XCTAssertNotEqual(base, withoutMeetingURL)
    }

    func testMenuMarkerStyleDistinguishesSymbolFamilies() {
        XCTAssertEqual(MenuMarkerStyle.allDay(.systemBlue), MenuMarkerStyle.allDay(.systemBlue))
        XCTAssertNotEqual(MenuMarkerStyle.color(.systemBlue), MenuMarkerStyle.reminder(.systemBlue))
        XCTAssertNotEqual(MenuMarkerStyle.birthday(.systemPink), MenuMarkerStyle.allDay(.systemPink))
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
    }

    func testReminderDueTextUsesAgoFormattingForOverdueItems() {
        let dueDate = Date(timeIntervalSince1970: 1_720_000_000)
        let now = dueDate.addingTimeInterval((2 * 3600) + (15 * 60))

        XCTAssertEqual(
            MenuContentView.reminderDueText(dueDate: dueDate, now: now, simplified: true),
            "2h ago"
        )
        XCTAssertEqual(
            MenuContentView.reminderDueText(dueDate: dueDate, now: now, simplified: false),
            "2h 15m ago"
        )
    }

    func testContextualActionItemsReturnAllActiveMapCandidates() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)

        let activeOne = makeUpcomingItem(
            id: "active-1",
            title: "Match A",
            startDate: now.addingTimeInterval(-900),
            endDate: now.addingTimeInterval(2700)
        )
        let activeTwo = makeUpcomingItem(
            id: "active-2",
            title: "Match B",
            startDate: now.addingTimeInterval(-1200),
            endDate: now.addingTimeInterval(1800)
        )
        let upcoming = makeUpcomingItem(
            id: "upcoming",
            title: "Match C",
            startDate: now.addingTimeInterval(900),
            endDate: now.addingTimeInterval(4500)
        )

        XCTAssertEqual(
            MenuContentView.contextualActionItems(from: [upcoming, activeTwo, activeOne], now: now).map(\.id),
            ["active-2", "active-1"]
        )
    }

    func testFootballContextualActionItemsOnlyReturnFootballMatches() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let activeMatchOne = makeFootballUpcomingItem(
            makeFootballMatch(
                id: "match-1",
                startDate: now.addingTimeInterval(-900),
                actualStartDate: now.addingTimeInterval(-840),
                statusState: .inProgress,
                statusText: "14'"
            )
        )
        let activeMeeting = makeUpcomingItem(
            id: "meeting-1",
            title: "Office meeting",
            startDate: now.addingTimeInterval(-1200),
            endDate: now.addingTimeInterval(1800)
        )
        let activeMatchTwo = makeFootballUpcomingItem(
            makeFootballMatch(
                id: "match-2",
                startDate: now.addingTimeInterval(-600),
                actualStartDate: now.addingTimeInterval(-540),
                statusState: .inProgress,
                statusText: "9'"
            )
        )

        XCTAssertEqual(
            MenuContentView.footballContextualActionItems(
                from: [activeMeeting, activeMatchTwo, activeMatchOne],
                now: now
            ).map(\.id),
            ["match-1", "match-2"]
        )
    }

    func testShouldShowContextualMapPreviewHidesFootballPreviewWhenThreeMatchesAreConcurrent() {
        let footballItem = makeFootballUpcomingItem(
            makeFootballMatch(
                id: "match-preview",
                startDate: Date(timeIntervalSince1970: 1_720_000_000),
                actualStartDate: nil,
                statusState: .scheduled,
                statusText: "7:00 PM"
            )
        )
        let regularItem = makeUpcomingItem(
            id: "meeting-preview",
            title: "Review",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            endDate: Date(timeIntervalSince1970: 1_720_000_000).addingTimeInterval(1800)
        )

        XCTAssertFalse(
            MenuContentView.shouldShowContextualMapPreview(
                for: footballItem,
                concurrentFootballMatchCount: 3
            )
        )
        XCTAssertTrue(
            MenuContentView.shouldShowContextualMapPreview(
                for: footballItem,
                concurrentFootballMatchCount: 2
            )
        )
        XCTAssertTrue(
            MenuContentView.shouldShowContextualMapPreview(
                for: regularItem,
                concurrentFootballMatchCount: 4
            )
        )
    }

    func testShouldShowContextualFootballGoalScorersIncludesUpToThreeMatchLayouts() {
        XCTAssertTrue(
            MenuContentView.shouldShowContextualFootballGoalScorers(for: 1)
        )
        XCTAssertTrue(
            MenuContentView.shouldShowContextualFootballGoalScorers(for: 2)
        )
        XCTAssertTrue(
            MenuContentView.shouldShowContextualFootballGoalScorers(for: 3)
        )
        XCTAssertFalse(
            MenuContentView.shouldShowContextualFootballGoalScorers(for: 4)
        )
    }

    func testFootballContextualScorePlacementMovesScoreToExpectedSection() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let liveMatch = makeFootballMatch(
            id: "live-score-placement",
            startDate: now.addingTimeInterval(-900),
            actualStartDate: now.addingTimeInterval(-840),
            statusState: .inProgress,
            statusText: "14'",
            homeScore: "2",
            awayScore: "1"
        )
        let scorelessMatch = makeFootballMatch(
            id: "scoreless-score-placement",
            startDate: now.addingTimeInterval(-900),
            actualStartDate: now.addingTimeInterval(-840),
            statusState: .inProgress,
            statusText: "14'",
            homeScore: "0",
            awayScore: "0"
        )

        XCTAssertEqual(
            MenuContentView.footballContextualScorePlacement(for: liveMatch, itemCount: 1),
            .stats
        )
        XCTAssertEqual(
            MenuContentView.footballContextualScorePlacement(for: liveMatch, itemCount: 2),
            .goalScorers
        )
        XCTAssertEqual(
            MenuContentView.footballContextualScorePlacement(for: scorelessMatch, itemCount: 2),
            .headline
        )
        XCTAssertEqual(
            MenuContentView.footballContextualScorePlacement(for: liveMatch, itemCount: 4),
            .headline
        )
    }

    func testExpandedContextualFootballHeaderStopsAtThreeConcurrentMatches() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let liveMatch = makeFootballMatch(
            id: "expanded-header-match",
            startDate: now.addingTimeInterval(-900),
            actualStartDate: now.addingTimeInterval(-840),
            statusState: .inProgress,
            statusText: "22'",
            homeScore: "1",
            awayScore: "0"
        )

        XCTAssertTrue(
            MenuContentView.shouldUseExpandedContextualFootballHeader(for: liveMatch, itemCount: 3)
        )
        XCTAssertFalse(
            MenuContentView.shouldUseExpandedContextualFootballHeader(for: liveMatch, itemCount: 4)
        )
    }

    func testFootballContextualScheduleTextOnlyShowsForFutureScheduledMatches() {
        let calendar = Calendar(identifier: .gregorian)
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let scheduledMatch = makeFootballMatch(
            id: "scheduled-match",
            startDate: now.addingTimeInterval(60 * 60),
            actualStartDate: nil,
            statusState: .scheduled,
            statusText: "1:00 PM"
        )
        let liveMatch = makeFootballMatch(
            id: "live-match",
            startDate: now.addingTimeInterval(-30 * 60),
            actualStartDate: now.addingTimeInterval(-28 * 60),
            statusState: .inProgress,
            statusText: "15'"
        )

        XCTAssertEqual(
            MenuContentView.footballContextualScheduleText(
                for: scheduledMatch,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            CalendarMonitor.footballScheduleText(
                for: scheduledMatch,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        )
        XCTAssertNil(
            MenuContentView.footballContextualScheduleText(
                for: liveMatch,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        )
    }

    func testQueueItemsForActionsExcludesFootballMatchesAlreadyStartedOrLive() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let liveMatch = makeFootballMatch(
            id: "live-match",
            startDate: now.addingTimeInterval(-900),
            actualStartDate: now.addingTimeInterval(-600),
            statusState: .inProgress,
            statusText: "15'"
        )
        let delayedMatch = makeFootballMatch(
            id: "delayed-match",
            startDate: now.addingTimeInterval(-120),
            actualStartDate: nil,
            statusState: .scheduled,
            statusText: "Starting soon"
        )
        let futureMatch = makeFootballMatch(
            id: "future-match",
            startDate: now.addingTimeInterval(1800),
            actualStartDate: nil,
            statusState: .scheduled,
            statusText: "7:30 PM"
        )
        let reminder = UpcomingItem(
            id: "reminder-1",
            title: "Pay bill",
            date: now.addingTimeInterval(1200),
            endDate: nil,
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: nil,
            calendarName: "Reminders",
            calendarColor: .systemBlue,
            kind: .reminder,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )

        let queued = MenuContentView.queueItemsForActions(
            from: [
                makeFootballUpcomingItem(liveMatch),
                makeFootballUpcomingItem(delayedMatch),
                makeFootballUpcomingItem(futureMatch),
                reminder,
            ],
            contextualItems: [],
            now: now,
            futureWindowEnd: now.addingTimeInterval(24 * 60 * 60),
            maxItems: 8
        )

        XCTAssertEqual(queued.map(\.id), ["future-match", "reminder-1"])
    }

    func testQueueItemsForActionsExcludesFootballMatchesDuplicatedInContextualPanel() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let contextualMatch = makeFootballMatch(
            id: "context-match",
            startDate: now.addingTimeInterval(1800),
            actualStartDate: nil,
            statusState: .scheduled,
            statusText: "7:30 PM"
        )
        let queueMatch = makeFootballMatch(
            id: "queue-match",
            startDate: now.addingTimeInterval(2400),
            actualStartDate: nil,
            statusState: .scheduled,
            statusText: "7:40 PM"
        )

        let queued = MenuContentView.queueItemsForActions(
            from: [
                makeFootballUpcomingItem(contextualMatch),
                makeFootballUpcomingItem(queueMatch),
            ],
            contextualItems: [
                makeFootballUpcomingItem(contextualMatch)
            ],
            now: now,
            futureWindowEnd: now.addingTimeInterval(24 * 60 * 60),
            maxItems: 8
        )

        XCTAssertEqual(queued.map(\.id), ["queue-match"])
    }

    func testQueueItemsForActionsExcludeContextualItemsToAvoidDuplicateRows() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let contextualEvent = makeUpcomingItem(
            id: "contextual-event",
            title: "Planning",
            startDate: now.addingTimeInterval(15 * 60),
            endDate: now.addingTimeInterval(45 * 60)
        )
        let queueEvent = makeUpcomingItem(
            id: "queue-event",
            title: "Review",
            startDate: now.addingTimeInterval(60 * 60),
            endDate: now.addingTimeInterval(90 * 60)
        )

        let queued = MenuContentView.queueItemsForActions(
            from: [contextualEvent, queueEvent],
            contextualItems: [contextualEvent],
            now: now,
            futureWindowEnd: now.addingTimeInterval(24 * 60 * 60),
            maxItems: 8
        )

        XCTAssertEqual(queued.map(\.id), ["queue-event"])
    }

    func testQueueItemsForActionsRespectsDropdownTimeWindowButKeepsAllDayAndActiveItems() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let futureWindowEnd = now.addingTimeInterval(2 * 60 * 60)
        let activeEvent = UpcomingItem(
            id: "active-event",
            title: "Match in progress",
            date: now.addingTimeInterval(-1800),
            endDate: now.addingTimeInterval(1800),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: nil,
            calendarName: "Work",
            calendarColor: .systemBlue,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
        let allDayEvent = UpcomingItem(
            id: "all-day",
            title: "Holiday",
            date: now,
            endDate: nil,
            isAllDay: true,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: "San Jose",
            meetingURL: nil,
            calendarID: nil,
            calendarName: "Personal",
            calendarColor: .systemGreen,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
        let nearFutureEvent = UpcomingItem(
            id: "near-future",
            title: "Planning",
            date: now.addingTimeInterval(90 * 60),
            endDate: now.addingTimeInterval(120 * 60),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: nil,
            calendarName: "Work",
            calendarColor: .systemOrange,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
        let farFutureEvent = UpcomingItem(
            id: "far-future",
            title: "Dinner",
            date: now.addingTimeInterval(6 * 60 * 60),
            endDate: now.addingTimeInterval(7 * 60 * 60),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: nil,
            calendarName: "Personal",
            calendarColor: .systemPink,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )

        let queued = MenuContentView.queueItemsForActions(
            from: [allDayEvent, activeEvent, nearFutureEvent, farFutureEvent],
            contextualItems: [],
            now: now,
            futureWindowEnd: futureWindowEnd,
            maxItems: 8
        )

        XCTAssertEqual(queued.map(\.id), ["all-day", "active-event", "near-future"])
    }

    func testResolvedMenuBarRotationStateKeepsCurrentSelectionWithinSameSlot() {
        let previousState = CalendarMonitor.MenuBarRotationState(
            slot: 42,
            selectedKey: "match-b",
            selectedIndex: 1
        )

        let resolvedState = CalendarMonitor.resolvedMenuBarRotationState(
            for: ["match-a", "match-b", "match-c"],
            slot: 42,
            previousState: previousState
        )

        XCTAssertEqual(resolvedState.slot, 42)
        XCTAssertEqual(resolvedState.selectedKey, "match-b")
        XCTAssertEqual(resolvedState.selectedIndex, 1)
    }

    func testResolvedMenuBarRotationStateAdvancesWhenSlotChanges() {
        let previousState = CalendarMonitor.MenuBarRotationState(
            slot: 42,
            selectedKey: "match-b",
            selectedIndex: 1
        )

        let resolvedState = CalendarMonitor.resolvedMenuBarRotationState(
            for: ["match-a", "match-b", "match-c"],
            slot: 43,
            previousState: previousState
        )

        XCTAssertEqual(resolvedState.slot, 43)
        XCTAssertEqual(resolvedState.selectedKey, "match-c")
        XCTAssertEqual(resolvedState.selectedIndex, 2)
    }

    func testTimedMenuBarRotationStateKeepsSelectionUntilIntervalExpires() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let previousState = CalendarMonitor.MenuBarRotationState(
            slot: 7,
            selectedKey: "match-b",
            selectedIndex: 1,
            startedAt: start
        )

        let resolvedState = CalendarMonitor.resolvedMenuBarRotationState(
            for: ["match-a", "match-b", "match-c"],
            now: start.addingTimeInterval(9),
            rotationInterval: 10,
            previousState: previousState,
            allowMissingSelectedKeyHold: false
        )

        XCTAssertEqual(resolvedState.slot, 7)
        XCTAssertEqual(resolvedState.selectedKey, "match-b")
        XCTAssertEqual(resolvedState.selectedIndex, 1)
        XCTAssertEqual(resolvedState.startedAt, start)
    }

    func testTimedMenuBarRotationStateAdvancesAfterFullInterval() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let previousState = CalendarMonitor.MenuBarRotationState(
            slot: 7,
            selectedKey: "match-b",
            selectedIndex: 1,
            startedAt: start
        )

        let advanceDate = start.addingTimeInterval(10)
        let resolvedState = CalendarMonitor.resolvedMenuBarRotationState(
            for: ["match-a", "match-b", "match-c"],
            now: advanceDate,
            rotationInterval: 10,
            previousState: previousState,
            allowMissingSelectedKeyHold: false
        )

        XCTAssertEqual(resolvedState.slot, 8)
        XCTAssertEqual(resolvedState.selectedKey, "match-c")
        XCTAssertEqual(resolvedState.selectedIndex, 2)
        XCTAssertEqual(resolvedState.startedAt, advanceDate)
    }

    func testTimedMenuBarRotationStateKeepsReplacementInsideUnifiedQueueWhenItemDisappearsMidInterval() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let previousState = CalendarMonitor.MenuBarRotationState(
            slot: 7,
            selectedKey: "match-b",
            selectedIndex: 1,
            startedAt: start
        )

        let resolvedState = CalendarMonitor.resolvedMenuBarRotationState(
            for: ["match-a", "match-c", "match-d"],
            now: start.addingTimeInterval(5),
            rotationInterval: 10,
            previousState: previousState,
            allowMissingSelectedKeyHold: false
        )

        XCTAssertEqual(resolvedState.slot, 7)
        XCTAssertEqual(resolvedState.selectedKey, "match-c")
        XCTAssertEqual(resolvedState.selectedIndex, 1)
        XCTAssertEqual(resolvedState.startedAt, start)
    }

    func testMenuBarRotationWindowIncludesActiveAndNearFutureItemsButExcludesFarFutureItems() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let activeEvent = UpcomingItem(
            id: "active-event",
            title: "Active",
            date: start.addingTimeInterval(-900),
            endDate: start.addingTimeInterval(900),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: nil,
            calendarName: "Work",
            calendarColor: .systemBlue,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
        let nearFutureEvent = UpcomingItem(
            id: "near-event",
            title: "Near",
            date: start.addingTimeInterval(45 * 60),
            endDate: start.addingTimeInterval(75 * 60),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: nil,
            calendarName: "Work",
            calendarColor: .systemGreen,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
        let farFutureEvent = UpcomingItem(
            id: "far-event",
            title: "Far",
            date: start.addingTimeInterval(3 * 60 * 60),
            endDate: start.addingTimeInterval(4 * 60 * 60),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: nil,
            calendarName: "Work",
            calendarColor: .systemOrange,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )

        XCTAssertTrue(
            CalendarMonitor.shouldIncludeTimedItemInMenuBarRotation(
                activeEvent,
                now: start,
                futureWindowSeconds: 60 * 60
            )
        )
        XCTAssertTrue(
            CalendarMonitor.shouldIncludeTimedItemInMenuBarRotation(
                nearFutureEvent,
                now: start,
                futureWindowSeconds: 60 * 60
            )
        )
        XCTAssertFalse(
            CalendarMonitor.shouldIncludeTimedItemInMenuBarRotation(
                farFutureEvent,
                now: start,
                futureWindowSeconds: 60 * 60
            )
        )
    }

    func testPreservedMenuBarSelectionKeyKeepsCurrentSelectionWhenPreferredPoolChangesWithinSameSlot() {
        let previousState = CalendarMonitor.MenuBarRotationState(
            slot: 42,
            selectedKey: "sunset",
            selectedIndex: 1
        )

        let preservedKey = CalendarMonitor.preservedMenuBarSelectionKeyIfNeeded(
            slot: 42,
            previousState: previousState,
            queueKeys: ["event-a", "sunset", "event-b"],
            preferredPoolKeys: ["event-a", "event-b"],
            allowMissingSelectedKeyHold: false
        )

        XCTAssertEqual(preservedKey, "sunset")
    }

    func testPreservedMenuBarSelectionKeyKeepsElapsedPointEventForRestOfSlot() {
        let previousState = CalendarMonitor.MenuBarRotationState(
            slot: 42,
            selectedKey: "sunset",
            selectedIndex: 1
        )

        let preservedKey = CalendarMonitor.preservedMenuBarSelectionKeyIfNeeded(
            slot: 42,
            previousState: previousState,
            queueKeys: ["event-a", "event-b"],
            preferredPoolKeys: ["event-a", "event-b"],
            allowMissingSelectedKeyHold: true
        )

        XCTAssertEqual(preservedKey, "sunset")
    }

    func testPreservedMenuBarSelectionKeyDoesNotKeepSelectionAfterSlotChanges() {
        let previousState = CalendarMonitor.MenuBarRotationState(
            slot: 42,
            selectedKey: "sunset",
            selectedIndex: 1
        )

        let preservedKey = CalendarMonitor.preservedMenuBarSelectionKeyIfNeeded(
            slot: 43,
            previousState: previousState,
            queueKeys: ["event-a", "event-b"],
            preferredPoolKeys: ["event-a", "event-b"],
            allowMissingSelectedKeyHold: true
        )

        XCTAssertNil(preservedKey)
    }

    func testUpdatedFootballGoalHighlightStaysPendingUntilMatchAppears() {
        let highlight = FootballGoalHighlight(matchID: "match-b", scoringSide: .home)

        let updated = CalendarMonitor.updatedFootballGoalHighlight(
            highlight,
            queueMatchIDs: ["match-a", "match-b", "match-c"],
            selectedMatchID: "match-a"
        )

        XCTAssertEqual(updated?.matchID, "match-b")
        XCTAssertEqual(updated?.scoringSide, .home)
        XCTAssertEqual(updated?.hasBeenShownInMenuBar, false)
    }

    func testUpdatedFootballGoalHighlightMarksFirstNaturalAppearance() {
        let highlight = FootballGoalHighlight(matchID: "match-b", scoringSide: .away)

        let updated = CalendarMonitor.updatedFootballGoalHighlight(
            highlight,
            queueMatchIDs: ["match-a", "match-b", "match-c"],
            selectedMatchID: "match-b"
        )

        XCTAssertEqual(updated?.matchID, "match-b")
        XCTAssertEqual(updated?.scoringSide, .away)
        XCTAssertEqual(updated?.hasBeenShownInMenuBar, true)
    }

    func testUpdatedFootballGoalHighlightClearsAfterConsumedAppearance() {
        let highlight = FootballGoalHighlight(
            matchID: "match-b",
            scoringSide: .away,
            hasBeenShownInMenuBar: true
        )

        let updated = CalendarMonitor.updatedFootballGoalHighlight(
            highlight,
            queueMatchIDs: ["match-a", "match-b", "match-c"],
            selectedMatchID: "match-c"
        )

        XCTAssertNil(updated)
    }

    func testShouldHoldElapsedPointInTimeMenuBarItemOnlyForPastInstantEvents() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let pastInstantEvent = UpcomingItem(
            id: "sunset",
            title: "Sunset",
            date: now.addingTimeInterval(-5),
            endDate: nil,
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: nil,
            calendarName: "Astronomy",
            calendarColor: .systemOrange,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
        let activeTimedEvent = UpcomingItem(
            id: "meeting",
            title: "Meeting",
            date: now.addingTimeInterval(-300),
            endDate: now.addingTimeInterval(300),
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
        let futureInstantEvent = UpcomingItem(
            id: "sunrise",
            title: "Sunrise",
            date: now.addingTimeInterval(120),
            endDate: nil,
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: nil,
            calendarName: "Astronomy",
            calendarColor: .systemYellow,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )

        XCTAssertTrue(CalendarMonitor.shouldHoldElapsedPointInTimeMenuBarItem(pastInstantEvent, now: now))
        XCTAssertFalse(CalendarMonitor.shouldHoldElapsedPointInTimeMenuBarItem(activeTimedEvent, now: now))
        XCTAssertFalse(CalendarMonitor.shouldHoldElapsedPointInTimeMenuBarItem(futureInstantEvent, now: now))
    }

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

    func testAutomaticAstronomyLocationAppActivationSkipsImmediateDuplicateLaunchRefresh() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertFalse(
            CalendarMonitor.shouldRefreshAutomaticAstronomyLocation(
                lastAttemptDate: now.addingTimeInterval(-45),
                now: now,
                trigger: .appActivation
            )
        )
        XCTAssertTrue(
            CalendarMonitor.shouldRefreshAutomaticAstronomyLocation(
                lastAttemptDate: now.addingTimeInterval(-61),
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
    }

    func testResolvedFootballSectionMatchesPrefersCachedEnrichedMatch() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let scheduledStart = now.addingTimeInterval(-10 * 60)
        let actualKickoff = now.addingTimeInterval(-3 * 60)
        let rawMatch = makeFootballMatch(
            id: "match-1",
            startDate: scheduledStart,
            actualStartDate: nil,
            statusState: .inProgress,
            statusText: "15'"
        )
        let cachedMatch = makeFootballMatch(
            id: "match-1",
            startDate: scheduledStart,
            actualStartDate: actualKickoff,
            statusState: .inProgress,
            statusText: "15'"
        )

        let resolved = CalendarMonitor.resolvedFootballSectionMatches(
            [rawMatch],
            cachedMatchesByID: [rawMatch.id: cachedMatch],
            now: now
        )

        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.actualStartDate, actualKickoff)
    }

    func testResolvedFootballSectionMatchesExcludeFixturesWithUnknownParticipants() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let knownMatch = makeFootballMatch(
            id: "known",
            startDate: now.addingTimeInterval(60 * 60),
            actualStartDate: nil,
            statusState: .scheduled,
            statusText: "7:00 PM"
        )
        let unknownMatch = FootballFixtureMatch(
            id: "unknown",
            competitionSlug: "uefa.champions",
            competitionName: "UEFA Champions League",
            competitionStage: "Semifinals",
            competitionLogoURL: nil,
            locationText: nil,
            startDate: now.addingTimeInterval(30 * 60),
            statusState: .scheduled,
            statusText: "TBD",
            homeTeam: FootballTeamSummary(
                id: "17631",
                name: "Quarterfinal 1 Winner",
                abbreviation: "QFW1",
                logoURL: nil,
                countryName: nil,
                isNational: false
            ),
            awayTeam: knownMatch.awayTeam,
            homeScore: "0",
            awayScore: "0"
        )

        let resolved = CalendarMonitor.resolvedFootballSectionMatches(
            [unknownMatch, knownMatch],
            cachedMatchesByID: [:],
            now: now
        )

        XCTAssertEqual(resolved.map(\.id), ["known"])
    }

    func testResolvedFootballSectionMatchesExcludeFixturesWithCompactPlaceholderSlots() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let knownMatch = makeFootballMatch(
            id: "known",
            startDate: now.addingTimeInterval(60 * 60),
            actualStartDate: nil,
            statusState: .scheduled,
            statusText: "7:00 PM"
        )
        let placeholderMatch = FootballFixtureMatch(
            id: "placeholder",
            competitionSlug: "fifa.world",
            competitionName: "FIFA World Cup",
            competitionStage: "Round of 16",
            competitionLogoURL: nil,
            locationText: nil,
            startDate: now.addingTimeInterval(30 * 60),
            statusState: .scheduled,
            statusText: "TBD",
            homeTeam: FootballTeamSummary(
                id: "ga2",
                name: "GA2",
                abbreviation: "GA2",
                logoURL: nil,
                countryName: nil,
                isNational: true
            ),
            awayTeam: FootballTeamSummary(
                id: "rd3",
                name: "RD3",
                abbreviation: "RD3",
                logoURL: nil,
                countryName: nil,
                isNational: true
            ),
            homeScore: "0",
            awayScore: "0"
        )

        let resolved = CalendarMonitor.resolvedFootballSectionMatches(
            [placeholderMatch, knownMatch],
            cachedMatchesByID: [:],
            now: now
        )

        XCTAssertEqual(resolved.map(\.id), ["known"])
    }

    private func makeUpcomingItem(id: String, title: String, startDate: Date, endDate: Date) -> UpcomingItem {
        UpcomingItem(
            id: id,
            title: title,
            date: startDate,
            endDate: endDate,
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: "Somewhere",
            meetingURL: nil,
            calendarID: "cal-1",
            calendarName: "Work",
            calendarColor: .systemBlue,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
    }

    private func makeFootballMatch(
        id: String,
        startDate: Date,
        actualStartDate: Date?,
        statusState: FootballFixtureStatusState,
        statusText: String,
        homeScore: String = "0",
        awayScore: String = "0"
    ) -> FootballFixtureMatch {
        FootballTestData.friendlyMatch(
            id: id,
            startDate: startDate,
            actualStartDate: actualStartDate,
            statusState: statusState,
            statusText: statusText,
            locationText: "Mercedes-Benz Stadium, Atlanta, Georgia, USA",
            homeTeam: FootballTestData.nationalTeam(
                id: "home-\(id)",
                name: "United States",
                abbreviation: "USA",
                countryName: "United States"
            ),
            awayTeam: FootballTestData.nationalTeam(
                id: "away-\(id)",
                name: "Portugal",
                abbreviation: "POR",
                countryName: "Portugal"
            ),
            homeScore: homeScore,
            awayScore: awayScore
        )
    }

    private func makeFootballUpcomingItem(_ match: FootballFixtureMatch) -> UpcomingItem {
        FootballTestData.upcomingFootballItem(
            for: match,
            endDate: match.startDate.addingTimeInterval(2 * 60 * 60)
        )
    }
}
