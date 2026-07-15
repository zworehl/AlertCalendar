import AppKit
import SwiftUI
import XCTest
@testable import AlertCalendar

final class FootballOutcomeProbabilityPresentationTests: AlertCalendarModelTestCase {
    func testCoordinatedRoundingAlwaysAllocatesOneHundredPercentagePoints() {
        XCTAssertEqual(
            FootballOutcomeProbabilityPresentation.roundedPercentagePoints([0.3334, 0.3333, 0.3333]),
            [34, 33, 33]
        )

        let rounded = FootballOutcomeProbabilityPresentation.roundedPercentagePoints([0.003, 0.067, 0.93])
        XCTAssertEqual(rounded, [0, 7, 93])
        XCTAssertEqual(rounded.reduce(0, +), 100)
    }

    func testNonzeroProbabilityBelowOnePercentUsesLessThanOneLabel() throws {
        let probabilities = try XCTUnwrap(
            FootballMatchOutcomeProbabilities(
                homeWin: 0.003,
                draw: 0.067,
                awayWin: 0.93,
                source: .heuristic,
                scope: .regulationTime
            )
        )

        let presentation = FootballOutcomeProbabilityPresentation(probabilities: probabilities)

        XCTAssertEqual(presentation.items.map(\.percentageText), ["<1%", "7%", "93%"])
        XCTAssertEqual(presentation.items.map(\.percentagePoints).reduce(0, +), 100)
    }

    func testNearCertainResultDoesNotClaimOneHundredPercentBesideTinyOutcomes() throws {
        let probabilities = try XCTUnwrap(
            FootballMatchOutcomeProbabilities(
                homeWin: 0.999,
                draw: 0.0005,
                awayWin: 0.0005,
                source: .heuristic,
                scope: .regulationTime
            )
        )

        let presentation = FootballOutcomeProbabilityPresentation(probabilities: probabilities)

        XCTAssertEqual(presentation.items.map(\.percentageText), [">99%", "<1%", "<1%"])
    }

    func testDecisiveResultContainsOnlyTwoRenormalizedTeamOutcomes() throws {
        let probabilities = try XCTUnwrap(
            FootballMatchOutcomeProbabilities(
                homeWin: 0.45,
                draw: 0,
                awayWin: 0.45,
                source: .heuristic,
                scope: .decisiveResult
            )
        )

        let presentation = FootballOutcomeProbabilityPresentation(probabilities: probabilities)

        XCTAssertEqual(presentation.scopeTitle, "Winner incl. penalties")
        XCTAssertEqual(presentation.items.map(\.outcome), [.homeWin, .awayWin])
        XCTAssertEqual(presentation.items.map(\.percentageText), ["50%", "50%"])
        XCTAssertEqual(presentation.segmentValues.reduce(0, +), 1, accuracy: 0.000_001)
    }

    func testRegulationAndExtraTimePossibleExplainNinetyMinuteHorizon() throws {
        for scope in [
            FootballMatchOutcomeProbabilityScope.regulationTime,
            FootballMatchOutcomeProbabilityScope.extraTimePossible,
        ] {
            let probabilities = try XCTUnwrap(
                FootballMatchOutcomeProbabilities(
                    homeWin: 0.40,
                    draw: 0.30,
                    awayWin: 0.30,
                    source: .marketOdds,
                    scope: scope
                )
            )

            let presentation = FootballOutcomeProbabilityPresentation(probabilities: probabilities)

            XCTAssertEqual(presentation.scopeTitle, "Regulation result")
            XCTAssertEqual(
                presentation.accessibilityScopeTitle,
                "Result at the end of regulation, including added time"
            )
            XCTAssertEqual(presentation.items.map(\.outcome), [.homeWin, .draw, .awayWin])
        }
    }

    func testFinalResultUsesPastTenseTitleAndVisibleSource() throws {
        let probabilities = try XCTUnwrap(
            FootballMatchOutcomeProbabilities(
                homeWin: 0,
                draw: 0,
                awayWin: 1,
                source: .finalResult,
                scope: .decisiveResult
            )
        )

        let presentation = FootballOutcomeProbabilityPresentation(probabilities: probabilities)

        XCTAssertEqual(presentation.scopeTitle, "Final result")
        XCTAssertEqual(presentation.accessibilityScopeTitle, "Final result")
        XCTAssertEqual(presentation.sourceTitle, "Final")
    }

    func testModelBasedOnMarketNamesItsSourcePrecisely() throws {
        let probabilities = try XCTUnwrap(
            FootballMatchOutcomeProbabilities(
                homeWin: 0.45,
                draw: 0.16,
                awayWin: 0.39,
                source: .heuristic,
                scope: .regulationTime,
                providerName: "Example Live Odds"
            )
        )

        let presentation = FootballOutcomeProbabilityPresentation(probabilities: probabilities)

        XCTAssertEqual(presentation.sourceTitle, "Model · Example Live Odds")
        XCTAssertEqual(
            presentation.sourceDescription,
            "Model estimate using Example Live Odds market odds"
        )
    }

    func testAccessibilitySummaryUsesFullTeamNamesAndOmitsDrawForDecisiveResult() throws {
        let probabilities = try XCTUnwrap(
            FootballMatchOutcomeProbabilities(
                homeWin: 0.62,
                draw: 0,
                awayWin: 0.38,
                source: .heuristic,
                scope: .decisiveResult
            )
        )
        let presentation = FootballOutcomeProbabilityPresentation(probabilities: probabilities)

        let summary = presentation.accessibilitySummary(
            homeTeamName: "United States",
            awayTeamName: "Portugal"
        )

        XCTAssertEqual(
            summary,
            "Winner, including extra time and penalties. United States win, 62 percent; Portugal win, 38 percent."
        )
        XCTAssertFalse(summary.contains("Draw"))
    }

    func testSegmentFramesRemainStrictlyProportionalWithoutMinimumWidths() {
        let frames = FootballOutcomeProbabilitySegmentLayout.frames(
            values: [0.004, 0.498, 0.498],
            totalWidth: 100
        )

        XCTAssertEqual(frames[0].width, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(frames[1].width, 49.8, accuracy: 0.000_001)
        XCTAssertEqual(frames[2].width, 49.8, accuracy: 0.000_001)
        XCTAssertEqual(frames[2].maxX, 100, accuracy: 0.000_001)
    }

    func testFailedOrEmptyStatisticsKeepSummaryContentVisible() {
        XCTAssertEqual(
            FootballMatchStatsPresentationState.resolve(
                statusState: .inProgress,
                statisticCount: 0,
                hasAttemptedLoad: true,
                isLoading: false
            ),
            .summary
        )
        XCTAssertEqual(
            FootballMatchStatsPresentationState.resolve(
                statusState: .inProgress,
                statisticCount: 0,
                hasAttemptedLoad: false,
                isLoading: true
            ),
            .loading
        )
        XCTAssertEqual(
            FootballMatchStatsPresentationState.resolve(
                statusState: .inProgress,
                statisticCount: 2,
                hasAttemptedLoad: true,
                isLoading: true
            ),
            .loaded
        )
        XCTAssertEqual(
            FootballMatchStatsPresentationState.resolve(
                statusState: .scheduled,
                statisticCount: 0,
                hasAttemptedLoad: true,
                isLoading: false
            ),
            .hidden
        )
    }
}

@MainActor
final class FootballOutcomeProbabilityBarLayoutTests: AlertCalendarModelTestCase {
    func testDecisiveProbabilityBarFitsNarrowContextualWidth() throws {
        _ = NSApplication.shared
        let width: CGFloat = 220
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let match = makeFootballMatch(
            id: "decisive-layout",
            startDate: now.addingTimeInterval(-110 * 60),
            actualStartDate: now.addingTimeInterval(-109 * 60),
            statusState: .inProgress,
            statusText: "105'",
            homeScore: "1",
            awayScore: "1"
        )
        let probabilities = try XCTUnwrap(
            FootballMatchOutcomeProbabilities(
                homeWin: 0.495,
                draw: 0,
                awayWin: 0.505,
                source: .heuristic,
                scope: .decisiveResult
            )
        )
        let view = FootballOutcomeProbabilityBar(
            match: match,
            display: nil,
            probabilities: probabilities,
            style: .contextual,
            availableWidth: width
        )
        let hostingView = NSHostingView(rootView: view.frame(maxWidth: width))
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 200)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertLessThanOrEqual(ceil(hostingView.fittingSize.width), width + 1)
        XCTAssertGreaterThanOrEqual(
            hostingView.fittingSize.height,
            FootballOutcomeProbabilityBar.Style.contextual.estimatedHeight - 2
        )
    }
}
