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
            shouldUseSplitDropdownLayout: false,
            dropdownMinimumWidth: 360,
            sharedContextualFootballMatches: nil,
            sharedContextualFootballCompetitionTitle: nil,
            sharedContextualFootballCompetitionLogoPath: nil,
            sharedContextualFootballCompetitionLogoURL: nil,
            contextualFootballLayoutItemCount: 0,
            contextualFootballContentLevel: .compact
        )

        XCTAssertEqual(menu.contextualPanelOuterWidth(snapshot: snapshot), 336)
        XCTAssertEqual(menu.contextualPanelContentWidth(snapshot: snapshot), 320)
        XCTAssertEqual(menu.upcomingPanelOuterWidth(snapshot: snapshot), 336)
        XCTAssertEqual(menu.upcomingPanelContentWidth(snapshot: snapshot), 320)
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
}
