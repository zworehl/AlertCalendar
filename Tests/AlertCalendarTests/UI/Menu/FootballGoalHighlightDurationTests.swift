import Foundation
import XCTest
@testable import AlertCalendar

final class FootballGoalHighlightDurationTests: AlertCalendarModelTestCase {
    func testPinnedMatchStopsHighlightingAtConfiguredIntervalDespiteRepeatedUpdates() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let match = FootballTestData.match(
            id: "pinned-match",
            startDate: now.addingTimeInterval(-900),
            statusState: .inProgress,
            homeScore: "1"
        )
        let nextEvent = makeUpcomingItem(
            id: "next-event",
            title: "Next event",
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(1800)
        )
        let candidates = CalendarMonitor.menuBarRotationCandidates(
            from: [FootballTestData.upcomingFootballItem(for: match), nextEvent],
            now: now,
            focusOnActiveEvents: true
        )
        XCTAssertEqual(candidates.map(\.id), [match.id])

        for interval: TimeInterval in [5, 30, 300] {
            let selectedMatchID = try XCTUnwrap(candidates.first?.footballMatch?.id)
            var highlight: FootballGoalHighlight? = FootballGoalHighlight(
                matchID: match.id,
                scoringSide: .home
            )
            for elapsed in 0..<Int(interval) {
                highlight = CalendarMonitor.updatedFootballGoalHighlight(
                    highlight,
                    queueMatchIDs: [match.id],
                    selectedMatchID: selectedMatchID,
                    now: now.addingTimeInterval(TimeInterval(elapsed)),
                    rotationInterval: interval
                )
                XCTAssertEqual(highlight?.scoringSide, .home)
                XCTAssertEqual(highlight?.firstShownInMenuBarAt, now)
            }

            for elapsed in [interval, interval + 1, interval * 2] {
                highlight = CalendarMonitor.updatedFootballGoalHighlight(
                    highlight,
                    queueMatchIDs: [match.id],
                    selectedMatchID: selectedMatchID,
                    now: now.addingTimeInterval(elapsed),
                    rotationInterval: interval
                )
                XCTAssertNil(highlight, "Pinned match must stop blinking after \(interval) seconds")
            }
        }
    }

    func testPendingGoalGetsFullIntervalWhenMatchFirstAppears() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let firstAppearance = now.addingTimeInterval(120)
        let pending = CalendarMonitor.updatedFootballGoalHighlight(
            FootballGoalHighlight(matchID: "match", scoringSide: .away),
            queueMatchIDs: ["match", "other-match"],
            selectedMatchID: "other-match",
            now: now,
            rotationInterval: 30
        )
        XCTAssertNotNil(pending)
        XCTAssertNil(pending?.firstShownInMenuBarAt)

        let shown = try XCTUnwrap(CalendarMonitor.updatedFootballGoalHighlight(
            pending,
            queueMatchIDs: ["match", "other-match"],
            selectedMatchID: "match",
            now: firstAppearance,
            rotationInterval: 30
        ))
        XCTAssertEqual(shown.firstShownInMenuBarAt, firstAppearance)
        XCTAssertNotNil(CalendarMonitor.updatedFootballGoalHighlight(
            shown,
            queueMatchIDs: ["match"],
            selectedMatchID: "match",
            now: firstAppearance.addingTimeInterval(29),
            rotationInterval: 30
        ))
        XCTAssertNil(CalendarMonitor.updatedFootballGoalHighlight(
            shown,
            queueMatchIDs: ["match"],
            selectedMatchID: "match",
            now: firstAppearance.addingTimeInterval(30),
            rotationInterval: 30
        ))
    }

    func testNewGoalStartsFreshIntervalWhileMatchRemainsSelected() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let firstGoal = FootballTestData.match(id: "match", statusState: .inProgress, homeScore: "1")
        let nextGoal = FootballTestData.match(id: "match", statusState: .inProgress, homeScore: "2")
        let firstHighlight = FootballGoalHighlight(
            matchID: "match",
            scoringSide: .home,
            firstShownInMenuBarAt: now
        )
        let nextGoalDate = now.addingTimeInterval(20)
        let newHighlight = try XCTUnwrap(CalendarMonitor.goalHighlight(
            from: firstGoal,
            to: nextGoal,
            now: nextGoalDate
        ))
        let shown = try XCTUnwrap(CalendarMonitor.updatedFootballGoalHighlight(
            newHighlight,
            queueMatchIDs: ["match"],
            selectedMatchID: "match",
            now: nextGoalDate,
            rotationInterval: 30
        ))
        XCTAssertEqual(shown.firstShownInMenuBarAt, nextGoalDate)
        XCTAssertNil(CalendarMonitor.updatedFootballGoalHighlight(
            firstHighlight,
            queueMatchIDs: ["match"],
            selectedMatchID: "match",
            now: now.addingTimeInterval(30),
            rotationInterval: 30
        ))
        XCTAssertNotNil(CalendarMonitor.updatedFootballGoalHighlight(
            shown,
            queueMatchIDs: ["match"],
            selectedMatchID: "match",
            now: nextGoalDate.addingTimeInterval(29),
            rotationInterval: 30
        ))
        XCTAssertNil(CalendarMonitor.updatedFootballGoalHighlight(
            shown,
            queueMatchIDs: ["match"],
            selectedMatchID: "match",
            now: nextGoalDate.addingTimeInterval(30),
            rotationInterval: 30
        ))
    }
}
