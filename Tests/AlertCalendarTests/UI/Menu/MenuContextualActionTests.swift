import AppKit
import Foundation
import XCTest
@testable import AlertCalendar

final class MenuContextualActionTests: AlertCalendarModelTestCase {
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
    func testSplitContextualActionItemsIncludeActiveMeetingWithAttendeesBeforeFootballMatch() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let activeMatch = makeFootballUpcomingItem(
            makeFootballMatch(
                id: "match-1",
                startDate: now.addingTimeInterval(-900),
                actualStartDate: now.addingTimeInterval(-840),
                statusState: .inProgress,
                statusText: "14'"
            )
        )
        let activeMeeting = UpcomingItem(
            id: "meeting-1",
            title: "Design review",
            date: now.addingTimeInterval(-600),
            endDate: now.addingTimeInterval(1800),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            organizer: MeetingOrganizer(displayText: "Ari", emailAddress: "ari@example.com"),
            attendees: [
                MeetingAttendee(
                    id: "sam@example.com",
                    displayText: "Sam",
                    emailAddress: "sam@example.com",
                    response: .accepted
                )
            ],
            calendarID: "calendar-1",
            calendarName: "Work",
            calendarColor: .systemBlue,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
        let previewKindsByKey: [String: MenuContentView.ContextualPreviewKind] = [
            activeMeeting.notificationKey: .attendees(activeMeeting.organizer, activeMeeting.attendees),
            activeMatch.notificationKey: .location("Mercedes-Benz Stadium, Atlanta, Georgia, USA"),
        ]

        let items = MenuContentView.splitContextualActionItems(
            contextualItems: [activeMatch, activeMeeting],
            footballItems: [activeMatch],
            previewKindsByKey: previewKindsByKey
        )

        XCTAssertEqual(items.map(\.id), ["meeting-1", "match-1"])
    }
    func testSplitContextualActionItemsKeepUpcomingEventWhenFootballMatchIsActive() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let activeMatch = makeFootballUpcomingItem(
            makeFootballMatch(
                id: "match-1",
                startDate: now.addingTimeInterval(-900),
                actualStartDate: now.addingTimeInterval(-840),
                statusState: .inProgress,
                statusText: "14'"
            )
        )
        let elevenOClockEvent = makeUpcomingItem(
            id: "event-11",
            title: "Design review",
            startDate: now.addingTimeInterval(30 * 60),
            endDate: now.addingTimeInterval(60 * 60)
        )
        let previewKindsByKey: [String: MenuContentView.ContextualPreviewKind] = [
            activeMatch.notificationKey: .location("Mercedes-Benz Stadium, Atlanta, Georgia, USA"),
            elevenOClockEvent.notificationKey: .location("Somewhere"),
        ]
        let contextualPreviewItems = MenuContentView.contextualActionItems(
            from: [activeMatch, elevenOClockEvent],
            now: now
        )
        let upcomingNonFootballItems = MenuContentView.contextualActionItems(
            from: [elevenOClockEvent],
            now: now
        )
        let footballItems = MenuContentView.footballContextualActionItems(
            from: [activeMatch, elevenOClockEvent],
            now: now
        )

        let items = MenuContentView.splitContextualActionItems(
            contextualItems: contextualPreviewItems + upcomingNonFootballItems,
            footballItems: footballItems,
            previewKindsByKey: previewKindsByKey
        )

        XCTAssertEqual(contextualPreviewItems.map(\.id), ["match-1"])
        XCTAssertEqual(items.map(\.id), ["match-1", "event-11"])
    }
    func testSplitContextualActionItemsDeduplicateMergedContextualItems() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let activeMatch = makeFootballUpcomingItem(
            makeFootballMatch(
                id: "match-1",
                startDate: now.addingTimeInterval(-900),
                actualStartDate: now.addingTimeInterval(-840),
                statusState: .inProgress,
                statusText: "14'"
            )
        )
        let activeRestriction = makeUpcomingItem(
            id: "vehicle-restriction",
            title: "Vehicle restriction",
            startDate: now.addingTimeInterval(-60 * 60),
            endDate: now.addingTimeInterval(10 * 60 * 60)
        )
        let previewKindsByKey: [String: MenuContentView.ContextualPreviewKind] = [
            activeMatch.notificationKey: .location("NRG Stadium"),
            activeRestriction.notificationKey: .location("San Jose"),
        ]

        let items = MenuContentView.splitContextualActionItems(
            contextualItems: [activeMatch, activeRestriction, activeRestriction],
            footballItems: [activeMatch],
            previewKindsByKey: previewKindsByKey
        )

        XCTAssertEqual(items.map(\.id), ["match-1", "vehicle-restriction"])
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
                contextualItemCount: 3
            )
        )
        XCTAssertTrue(
            MenuContentView.shouldShowContextualMapPreview(
                for: footballItem,
                contextualItemCount: 2
            )
        )
        XCTAssertTrue(
            MenuContentView.shouldShowContextualMapPreview(
                for: regularItem,
                contextualItemCount: 4
            )
        )
    }

    func testContainsOnlyAstronomyItemsDetectsTransientAstronomyOnlyQueue() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let astronomyItems = [
            makeUpcomingItem(id: "sunset", title: "Sunset", startDate: now, endDate: now.addingTimeInterval(60)),
            makeUpcomingItem(id: "solar-midnight", title: "Solar Midnight", startDate: now, endDate: now.addingTimeInterval(60)),
            makeUpcomingItem(id: "sunrise", title: "Sunrise", startDate: now, endDate: now.addingTimeInterval(60)),
            makeUpcomingItem(id: "solar-noon", title: "Solar Noon", startDate: now, endDate: now.addingTimeInterval(60)),
        ]
        let meeting = makeUpcomingItem(
            id: "meeting",
            title: "Replatform QA Check In",
            startDate: now,
            endDate: now.addingTimeInterval(30 * 60)
        )

        XCTAssertTrue(MenuContentView.containsOnlyAstronomyItems(astronomyItems))
        XCTAssertFalse(MenuContentView.containsOnlyAstronomyItems(astronomyItems + [meeting]))
        XCTAssertFalse(MenuContentView.containsOnlyAstronomyItems([]))
    }

    func testFootballContextualContentLevelCountsRegularConcurrentEvents() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let footballItem = makeFootballUpcomingItem(
            makeFootballMatch(
                id: "match-with-event",
                startDate: now.addingTimeInterval(-900),
                actualStartDate: now.addingTimeInterval(-840),
                statusState: .inProgress,
                statusText: "14'",
                homeScore: "1",
                awayScore: "0"
            )
        )
        let regularItem = makeUpcomingItem(
            id: "concurrent-event",
            title: "Design review",
            startDate: now.addingTimeInterval(-600),
            endDate: now.addingTimeInterval(1800)
        )

        let itemCount = MenuContentView.contextualFootballLayoutItemCount(
            from: [footballItem, regularItem]
        )
        let contentLevel = MenuContentView.contextualFootballContentLevel(for: itemCount)

        XCTAssertEqual(itemCount, 2)
        XCTAssertFalse(contentLevel.showsStats)
        XCTAssertTrue(contentLevel.showsGoalScorers)
        XCTAssertEqual(
            MenuContentView.footballContextualScorePlacement(
                for: try! XCTUnwrap(footballItem.footballMatch),
                itemCount: itemCount
            ),
            .goalScorers
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
    func testStandaloneContextualFootballOutcomeProbabilitiesShowForTwoPreviewLayouts() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let liveMatch = makeFootballMatch(
            id: "live-outcome-probabilities",
            startDate: now.addingTimeInterval(-900),
            actualStartDate: now.addingTimeInterval(-840),
            statusState: .inProgress,
            statusText: "14'",
            homeScore: "1",
            awayScore: "0"
        )
        let scheduledMatch = makeFootballMatch(
            id: "scheduled-outcome-probabilities",
            startDate: now.addingTimeInterval(60 * 60),
            actualStartDate: nil,
            statusState: .scheduled,
            statusText: "7:00 PM"
        )

        XCTAssertFalse(
            MenuContentView.shouldShowStandaloneContextualFootballOutcomeProbabilities(
                for: liveMatch,
                itemCount: 1
            )
        )
        XCTAssertTrue(
            MenuContentView.shouldShowStandaloneContextualFootballOutcomeProbabilities(
                for: liveMatch,
                itemCount: 2
            )
        )
        XCTAssertTrue(
            MenuContentView.shouldShowStandaloneContextualFootballOutcomeProbabilities(
                for: scheduledMatch,
                itemCount: 1
            )
        )
        XCTAssertFalse(
            MenuContentView.shouldShowStandaloneContextualFootballOutcomeProbabilities(
                for: liveMatch,
                itemCount: 3
            )
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

    func testAttendeePreviewListHeightShrinksToFitShortContent() {
        XCTAssertEqual(
            MeetingAttendeesPreview.resolvedListHeight(attendeeCount: 2, maximumHeight: 188),
            34
        )
        XCTAssertEqual(
            MeetingAttendeesPreview.resolvedListHeight(attendeeCount: 10, maximumHeight: 188),
            138
        )
    }

    func testAttendeePreviewListHeightCapsAtMaximumForLongContent() {
        XCTAssertEqual(
            MeetingAttendeesPreview.resolvedListHeight(attendeeCount: 14, maximumHeight: 188),
            188
        )
    }

    func testAttendeePreviewListHeightSupportsSingleColumnSplitLayout() {
        XCTAssertEqual(
            MeetingAttendeesPreview.resolvedListHeight(attendeeCount: 2, maximumHeight: 148, columnCount: 1),
            60
        )
        XCTAssertEqual(
            MeetingAttendeesPreview.resolvedListHeight(attendeeCount: 10, maximumHeight: 148, columnCount: 1),
            148
        )
    }
}
