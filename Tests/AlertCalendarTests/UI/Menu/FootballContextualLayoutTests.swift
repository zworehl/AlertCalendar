import AppKit
import SwiftUI
import XCTest
@testable import AlertCalendar

@MainActor
final class FootballContextualLayoutTests: AlertCalendarModelTestCase {
    func testFootballContextualPreviewViewsRespectNarrowMenuWidth() throws {
        let width: CGFloat = 320
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeFootballMatch(
            id: "narrow-live",
            startDate: now.addingTimeInterval(-55 * 60),
            actualStartDate: now.addingTimeInterval(-54 * 60),
            statusState: .inProgress,
            statusText: "45'+3'",
            homeScore: "0",
            awayScore: "1"
        )
        let probabilities = try XCTUnwrap(
            FootballMatchOutcomeProbabilities(
                homeWin: 0.66,
                draw: 0.24,
                awayWin: 0.10,
                source: .heuristic,
                scope: .extraTimePossible
            )
        )
        let stats = [
            FootballMatchStatistic(
                id: "possession",
                label: "Possession",
                homeValue: "59.3%",
                awayValue: "40.7%"
            ),
            FootballMatchStatistic(
                id: "shots-on-target",
                label: "Shots on target",
                homeValue: "3",
                awayValue: "1"
            ),
        ]

        let sizes = [
            fittingSize(
                of: FootballMatchSectionHeaderView(
                    match: match,
                    display: nil,
                    showsScore: true,
                    showsTeamNames: true,
                    showsTeamLogos: true,
                    availableWidth: width
                ),
                width: width
            ),
            fittingSize(
                of: FootballOutcomeProbabilityBar(
                    match: match,
                    display: nil,
                    probabilities: probabilities,
                    style: .contextual,
                    availableWidth: width
                ),
                width: width
            ),
            fittingSize(
                of: FootballMatchStatsView(
                    match: match,
                    display: nil,
                    stats: stats,
                    showsScore: true,
                    outcomeProbabilities: probabilities,
                    availableWidth: width
                ),
                width: width
            ),
            fittingSize(
                of: FootballGoalScorersLoadingView(
                    match: match,
                    display: nil,
                    showsHeader: true,
                    showsScore: true,
                    availableWidth: width
                ),
                width: width
            ),
        ]

        for size in sizes {
            XCTAssertLessThanOrEqual(ceil(size.width), width + 1)
        }
    }

    func testGoalScorersKeepTeamColumnsWhenOnlyOneTeamScored() {
        let width: CGFloat = 320
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeFootballMatch(
            id: "single-scorer",
            startDate: now.addingTimeInterval(-20 * 60),
            actualStartDate: now.addingTimeInterval(-19 * 60),
            statusState: .inProgress,
            statusText: "20'",
            homeScore: "0",
            awayScore: "1"
        )
        let scorers = FootballMatchGoalScorers(
            home: [],
            away: [
                FootballMatchGoalScorer(
                    id: "single-scorer-away-0",
                    name: "Brian Cipenga",
                    minute: "7'"
                ),
            ]
        )

        XCTAssertTrue(
            FootballGoalScorersView.usesTwoScorerColumns(
                homeScorerCount: scorers.home.count,
                awayScorerCount: scorers.away.count
            )
        )

        let size = fittingSize(
            of: FootballGoalScorersView(
                match: match,
                display: nil,
                scorers: scorers,
                showsHeader: false,
                showsScore: false,
                availableWidth: width
            ),
            width: width
        )

        XCTAssertLessThanOrEqual(ceil(size.width), width + 1)
    }

    func testGoalScorerRowsStaySingleLineForLongNames() {
        let width: CGFloat = 320
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeFootballMatch(
            id: "long-scorer",
            startDate: now.addingTimeInterval(-55 * 60),
            actualStartDate: now.addingTimeInterval(-54 * 60),
            statusState: .inProgress,
            statusText: "55'",
            homeScore: "1",
            awayScore: "1"
        )
        let compactScorers = FootballMatchGoalScorers(
            home: [
                FootballMatchGoalScorer(
                    id: "long-scorer-home-0",
                    name: "M. Hany",
                    minute: "55'"
                ),
            ],
            away: [
                FootballMatchGoalScorer(
                    id: "long-scorer-away-0",
                    name: "Emam Ashour",
                    minute: "13'"
                ),
            ]
        )
        let longScorers = FootballMatchGoalScorers(
            home: [
                FootballMatchGoalScorer(
                    id: "long-scorer-home-0",
                    name: "Mohamed Hany (Own Goal)",
                    minute: "55'"
                ),
            ],
            away: compactScorers.away
        )

        let compactSize = fittingSize(
            of: FootballGoalScorersView(
                match: match,
                display: nil,
                scorers: compactScorers,
                showsHeader: false,
                showsScore: false,
                availableWidth: width
            ),
            width: width
        )
        let longSize = fittingSize(
            of: FootballGoalScorersView(
                match: match,
                display: nil,
                scorers: longScorers,
                showsHeader: false,
                showsScore: false,
                availableWidth: width
            ),
            width: width
        )

        XCTAssertLessThanOrEqual(ceil(longSize.width), width + 1)
        XCTAssertLessThanOrEqual(longSize.height, compactSize.height + 1)
    }

    func testMenuPanelContentWidthTracksSingleColumnDropdownWidth() {
        let menu = MenuContentView(kindFilter: nil, headerTitle: "Alert Calendar")
        let minimumWidthSnapshot = layoutSnapshot(dropdownMinimumWidth: 260)
        let measuredWidthSnapshot = layoutSnapshot(dropdownMinimumWidth: 360)

        XCTAssertEqual(menu.contextualPanelOuterWidth(snapshot: minimumWidthSnapshot), 236)
        XCTAssertEqual(menu.contextualPanelContentWidth(snapshot: minimumWidthSnapshot), 220)
        XCTAssertEqual(menu.upcomingPanelOuterWidth(snapshot: minimumWidthSnapshot), 236)
        XCTAssertEqual(menu.upcomingPanelContentWidth(snapshot: minimumWidthSnapshot), 220)
        XCTAssertEqual(menu.contextualPanelOuterWidth(snapshot: measuredWidthSnapshot), 336)
        XCTAssertEqual(menu.contextualPanelContentWidth(snapshot: measuredWidthSnapshot), 320)
        XCTAssertEqual(menu.upcomingPanelOuterWidth(snapshot: measuredWidthSnapshot), 336)
        XCTAssertEqual(menu.upcomingPanelContentWidth(snapshot: measuredWidthSnapshot), 320)
    }

    private func layoutSnapshot(dropdownMinimumWidth: CGFloat) -> MenuContentView.LayoutSnapshot {
        MenuContentView.LayoutSnapshot(
            filteredAlertDescriptions: [],
            contextualActionCandidates: [],
            contextualPreviewActionItems: [],
            footballContextualActionItems: [],
            displayedContextualActionItems: [],
            contextualPreviewKindsByKey: [:],
            queueItemsSource: [],
            queueItemsForSingleColumnLayout: [],
            queueItemsForSplitLayout: [],
            queueItemsForActions: [],
            shouldUseSplitDropdownLayout: false,
            dropdownMinimumWidth: dropdownMinimumWidth,
            sharedContextualFootballMatches: nil,
            sharedContextualFootballCompetitionTitle: nil,
            sharedContextualFootballCompetitionLogoPath: nil,
            sharedContextualFootballCompetitionLogoURL: nil,
            contextualFootballLayoutItemCount: 0,
            contextualFootballContentLevel: .compact
        )
    }

    func testSingleColumnDropdownWidthFollowsMeasuredContent() {
        let menu = MenuContentView(kindFilter: nil, headerTitle: "Alert Calendar")

        XCTAssertEqual(
            menu.resolvedSingleColumnDropdownWidth(contextualWidth: 360, queueWidth: 380),
            380
        )
        XCTAssertEqual(
            menu.resolvedSingleColumnDropdownWidth(contextualWidth: 460, queueWidth: 500),
            500
        )
    }

    func testScrollableUpcomingActionsReserveScrollbarHitArea() {
        let menu = MenuContentView(kindFilter: nil, headerTitle: "Alert Calendar")
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let item = dropdownHeightItem(
            startDate: now,
            endDate: now.addingTimeInterval(30 * 60),
            isAllDay: false
        )
        let scrollbarInset = MenuContentView.actionTrailingInset(
            showsVerticalScrollIndicator: true,
            scrollerWidth: 17
        )
        let rowWidth: CGFloat = 320
        let baseTrailingPadding: CGFloat = 2
        let actionRightEdge = rowWidth - baseTrailingPadding - scrollbarInset
        let scrollbarLeftEdge = rowWidth - 17

        XCTAssertEqual(scrollbarInset, 17)
        XCTAssertLessThan(actionRightEdge, scrollbarLeftEdge)
        XCTAssertEqual(scrollbarLeftEdge - actionRightEdge, baseTrailingPadding)
        XCTAssertEqual(
            MenuContentView.actionTrailingInset(
                showsVerticalScrollIndicator: false,
                scrollerWidth: 17
            ),
            0
        )
        XCTAssertEqual(
            menu.hoverActionRowWidth(for: item, trailingInset: scrollbarInset),
            menu.hoverActionRowWidth(for: item) + scrollbarInset
        )
    }

    func testDropdownHoverHeightPreservationOnlyAppliesToTimedEventsCrossingDays() {
        let menu = MenuContentView(kindFilter: nil, headerTitle: "Alert Calendar")
        let calendar = Calendar(identifier: .gregorian)
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 23, minute: 25))!
        let sameDayEndDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 23, minute: 55))!
        let nextDayEndDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: 0, minute: 25))!
        let timedSameDay = dropdownHeightItem(
            startDate: startDate,
            endDate: sameDayEndDate,
            isAllDay: false
        )
        let timedCrossDay = dropdownHeightItem(
            startDate: startDate,
            endDate: nextDayEndDate,
            isAllDay: false
        )
        let allDayCrossDay = dropdownHeightItem(
            startDate: calendar.startOfDay(for: startDate),
            endDate: calendar.startOfDay(for: nextDayEndDate),
            isAllDay: true
        )

        XCTAssertFalse(MenuContentView.shouldPreserveDropdownHoverHeight(for: timedSameDay))
        XCTAssertTrue(MenuContentView.shouldPreserveDropdownHoverHeight(for: timedCrossDay))
        XCTAssertFalse(MenuContentView.shouldPreserveDropdownHoverHeight(for: allDayCrossDay))

        XCTAssertNil(
            menu.rowPrimaryContentMinimumHeight(
                for: timedSameDay,
                showsTravelTime: false,
                showRightTimeColumn: true
            )
        )
        XCTAssertEqual(
            menu.rowPrimaryContentMinimumHeight(
                for: timedCrossDay,
                showsTravelTime: false,
                showRightTimeColumn: true
            ),
            44
        )
        XCTAssertNil(
            menu.rowPrimaryContentMinimumHeight(
                for: allDayCrossDay,
                showsTravelTime: false,
                showRightTimeColumn: true
            )
        )
    }

    func testSplitContextualPanelWidthUsesContentMinimumInsteadOfFixedColumn() {
        let menu = MenuContentView(kindFilter: nil, headerTitle: "Alert Calendar")

        XCTAssertEqual(
            menu.splitContextualPanelOuterWidth(contextualItems: [], previewKindsByKey: [:]),
            336
        )
        XCTAssertEqual(
            menu.splitDropdownWidth(contextualItems: [], previewKindsByKey: [:]),
            708
        )
    }

    func testSplitUpcomingPanelHeightTracksMeasuredContentBelowLimit() {
        _ = NSApplication.shared
        let menu = MenuContentView(kindFilter: nil, headerTitle: "Alert Calendar")
        let snapshot = MenuContentView.LayoutSnapshot(
            filteredAlertDescriptions: [],
            contextualActionCandidates: [],
            contextualPreviewActionItems: [],
            footballContextualActionItems: [],
            displayedContextualActionItems: [],
            contextualPreviewKindsByKey: [:],
            queueItemsSource: [],
            queueItemsForSingleColumnLayout: [],
            queueItemsForSplitLayout: [],
            queueItemsForActions: [],
            shouldUseSplitDropdownLayout: true,
            dropdownMinimumWidth: 708,
            sharedContextualFootballMatches: nil,
            sharedContextualFootballCompetitionTitle: nil,
            sharedContextualFootballCompetitionLogoPath: nil,
            sharedContextualFootballCompetitionLogoURL: nil,
            contextualFootballLayoutItemCount: 0,
            contextualFootballContentLevel: .compact
        )

        XCTAssertEqual(menu.splitPanelHeight(measuredHeight: 180, snapshot: snapshot), 180)
        XCTAssertEqual(
            menu.splitPanelHeight(measuredHeight: 10_000, snapshot: snapshot),
            menu.splitDropdownColumnHeightLimit
        )
        XCTAssertEqual(
            menu.splitContextualPanelMinimumHeight(
                snapshot: snapshot,
                measuredRightColumnHeight: 480,
                measuredContextualPanelHeight: 500
            ),
            500
        )
        XCTAssertEqual(
            menu.splitContextualPanelMinimumHeight(
                snapshot: snapshot,
                measuredRightColumnHeight: 480,
                measuredContextualPanelHeight: 10_000
            ),
            10_000
        )
        XCTAssertNil(
            menu.splitContextualPanelMinimumHeight(
                snapshot: snapshot,
                measuredRightColumnHeight: 0,
                measuredContextualPanelHeight: 0
            )
        )

        let stretchedPanelSize = fittingSize(
            of: menu.calendarSectionContainer(minimumHeight: 564) {
                Color.clear.frame(height: 20)
            },
            width: 336
        )
        XCTAssertEqual(stretchedPanelSize.height, 564, accuracy: 1)
    }

    func testSplitAttendeePreviewUsesRemainingHeightAlongsideLocationPreview() {
        let menu = MenuContentView(kindFilter: nil, headerTitle: "Alert Calendar")
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let organizer = MeetingOrganizer(
            displayText: "Madison",
            emailAddress: "madison@getzilker.com"
        )
        let attendees = (0..<31).map { index in
            MeetingAttendee(
                id: "attendee-\(index)",
                displayText: "Invitee \(index)",
                emailAddress: "invitee\(index)@example.com",
                response: .accepted
            )
        }
        let firstItem = UpcomingItem(
            id: "standup",
            title: "Replatform Team Stand up",
            date: now,
            endDate: now.addingTimeInterval(30 * 60),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: URL(string: "https://meet.google.com/example"),
            organizer: organizer,
            attendees: attendees,
            calendarID: "work",
            calendarName: "Work",
            calendarColor: .systemGreen,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
        let secondItem = UpcomingItem(
            id: "outage",
            title: "Electricity Outage",
            date: now.addingTimeInterval(60 * 60),
            endDate: now.addingTimeInterval(10 * 60 * 60),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: "Calle 90, San José",
            meetingURL: nil,
            calendarID: "utilities",
            calendarName: "Utilities",
            calendarColor: .systemRed,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
        let snapshot = MenuContentView.LayoutSnapshot(
            filteredAlertDescriptions: [],
            contextualActionCandidates: [firstItem, secondItem],
            contextualPreviewActionItems: [firstItem, secondItem],
            footballContextualActionItems: [],
            displayedContextualActionItems: [firstItem, secondItem],
            contextualPreviewKindsByKey: [
                firstItem.notificationKey: .attendees(organizer, attendees),
                secondItem.notificationKey: .location("Calle 90, San José"),
            ],
            queueItemsSource: [],
            queueItemsForSingleColumnLayout: [],
            queueItemsForSplitLayout: [],
            queueItemsForActions: [],
            shouldUseSplitDropdownLayout: true,
            dropdownMinimumWidth: 708,
            sharedContextualFootballMatches: nil,
            sharedContextualFootballCompetitionTitle: nil,
            sharedContextualFootballCompetitionLogoPath: nil,
            sharedContextualFootballCompetitionLogoURL: nil,
            contextualFootballLayoutItemCount: 0,
            contextualFootballContentLevel: .compact
        )

        let expandedListHeight = menu.attendeePreviewMaximumListHeight(
            for: firstItem,
            snapshot: snapshot,
            targetPanelHeight: 564,
            compactPanelHeight: 480
        )

        XCTAssertEqual(expandedListHeight, 232)
        XCTAssertGreaterThan(expandedListHeight, 148)
        XCTAssertEqual(
            MeetingAttendeesPreview.resolvedListHeight(
                attendeeCount: attendees.count,
                maximumHeight: expandedListHeight,
                columnCount: 1
            ),
            expandedListHeight
        )
    }

    private func fittingSize<Content: View>(
        of content: Content,
        width: CGFloat
    ) -> CGSize {
        let hostingView = NSHostingView(rootView: content.frame(maxWidth: width))
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 1_000)
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize
    }

    private func dropdownHeightItem(
        startDate: Date,
        endDate: Date,
        isAllDay: Bool
    ) -> UpcomingItem {
        UpcomingItem(
            id: UUID().uuidString,
            title: "School break",
            date: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: "school",
            calendarName: "School",
            calendarColor: .systemBlue,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
    }
}
