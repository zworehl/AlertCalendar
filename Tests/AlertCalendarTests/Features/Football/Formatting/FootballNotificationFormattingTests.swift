import XCTest
@testable import AlertCalendar

final class FootballNotificationFormattingTests: FootballFixtureFormatterTestCase {
    let startDate = Date(timeIntervalSince1970: 1_720_000_000)

    func testGoalNotificationUsesSoberScorerMessage() {
        let match = makeMatch(
            id: "goal-message",
            startDate: startDate,
            statusState: .inProgress,
            homeScore: "1",
            awayScore: "2"
        )
        let scorer = FootballMatchGoalScorer(
            id: "away-67-3",
            name: "Juan Perez",
            minute: "67'"
        )

        let message = CalendarMonitor.footballGoalNotificationMessage(
            for: match,
            scoringSide: .away,
            scorer: scorer,
            includeScorerName: true
        )

        XCTAssertEqual(message.title, "\(match.awayTeam.name) goal")
        XCTAssertEqual(
            message.body,
            "Juan Perez scored at 67'. \(match.homeTeam.name) 1-2 \(match.awayTeam.name)."
        )
    }

    func testGoalNotificationFallsBackToTeamWhenScorerIsDisabled() {
        let match = makeMatch(
            id: "goal-message-no-scorer",
            startDate: startDate,
            statusState: .inProgress,
            homeScore: "2",
            awayScore: "1"
        )
        let scorer = FootballMatchGoalScorer(
            id: "home-81-5",
            name: "Alex Morgan",
            minute: "81'"
        )

        let message = CalendarMonitor.footballGoalNotificationMessage(
            for: match,
            scoringSide: .home,
            scorer: scorer,
            includeScorerName: false
        )

        XCTAssertEqual(message.title, "\(match.homeTeam.name) goal")
        XCTAssertEqual(
            message.body,
            "\(match.homeTeam.name) scored. \(match.homeTeam.name) 2-1 \(match.awayTeam.name)."
        )
    }

    func testFinalNotificationUsesFinalScoreOnly() {
        let match = makeMatch(
            id: "final-message",
            startDate: startDate,
            statusState: .finished,
            homeScore: "3",
            awayScore: "1"
        )

        let message = CalendarMonitor.footballFinalNotificationMessage(for: match)

        XCTAssertEqual(message.title, "Match finished")
        XCTAssertEqual(message.body, "\(match.homeTeam.name) 3-1 \(match.awayTeam.name).")
    }

    func testDisallowedGoalNotificationUsesAdjustedScore() {
        let match = makeMatch(
            id: "disallowed-goal-message",
            startDate: startDate,
            statusState: .inProgress,
            homeScore: "1",
            awayScore: "1"
        )

        let message = CalendarMonitor.footballDisallowedGoalNotificationMessage(
            for: match,
            disallowedSide: .home
        )

        XCTAssertEqual(message.title, "\(match.homeTeam.name) goal disallowed")
        XCTAssertEqual(
            message.body,
            "\(match.homeTeam.name) had a goal ruled out. \(match.homeTeam.name) 1-1 \(match.awayTeam.name)."
        )
    }

    func testAutoAddNotificationSummarizesAddedMatch() {
        let match = makeMatch(
            id: "auto-add-message",
            startDate: startDate.addingTimeInterval(3_600),
            statusState: .scheduled
        )

        let message = CalendarMonitor.footballAutoAddNotificationMessage(
            for: match,
            now: startDate
        )

        XCTAssertEqual(message.title, "Match added to Calendar")
        XCTAssertTrue(message.body.contains(match.competitionName))
        XCTAssertTrue(message.body.contains("\(match.homeTeam.name) vs \(match.awayTeam.name)"))
    }

    func testAutoAddNotificationKeyUsesMatchID() {
        let match = makeMatch(
            id: "auto-add-key",
            startDate: startDate,
            statusState: .scheduled
        )

        XCTAssertEqual(
            CalendarMonitor.footballAutoAddNotificationKey(for: match),
            "football.autoAdd.auto-add-key"
        )
    }

    func testDisallowedGoalNotificationKeyIncludesScoreCorrection() {
        let previous = makeMatch(
            id: "disallowed-goal-key",
            startDate: startDate,
            statusState: .inProgress,
            homeScore: "2",
            awayScore: "1"
        )
        let current = makeMatch(
            id: "disallowed-goal-key",
            startDate: startDate,
            statusState: .inProgress,
            homeScore: "1",
            awayScore: "1"
        )

        XCTAssertEqual(
            CalendarMonitor.footballDisallowedGoalNotificationKey(
                from: previous,
                to: current,
                disallowedSide: .home
            ),
            "football.disallowedGoal.disallowed-goal-key.home.2.2-1.to.1-1"
        )
    }

    func testFinalNotificationRequiresTransitionIntoFinished() {
        let previous = makeMatch(
            id: "final-transition",
            startDate: startDate,
            statusState: .inProgress,
            homeScore: "1",
            awayScore: "1"
        )
        let current = makeMatch(
            id: "final-transition",
            startDate: startDate,
            statusState: .finished,
            homeScore: "2",
            awayScore: "1"
        )
        let alreadyFinished = makeMatch(
            id: "final-transition",
            startDate: startDate,
            statusState: .finished,
            homeScore: "2",
            awayScore: "1"
        )

        XCTAssertTrue(CalendarMonitor.footballFinishedTransition(from: previous, to: current))
        XCTAssertFalse(CalendarMonitor.footballFinishedTransition(from: current, to: alreadyFinished))
    }

    func testDisallowedGoalTransitionDetectsSingleSideScoreDecrease() {
        let previous = makeMatch(
            id: "disallowed-goal-transition",
            startDate: startDate,
            statusState: .inProgress,
            homeScore: "1",
            awayScore: "2"
        )
        let current = makeMatch(
            id: "disallowed-goal-transition",
            startDate: startDate,
            statusState: .inProgress,
            homeScore: "1",
            awayScore: "1"
        )

        XCTAssertEqual(
            CalendarMonitor.footballDisallowedGoalSide(from: previous, to: current),
            .away
        )
    }

    func testDisallowedGoalTransitionIgnoresMultiSideCorrections() {
        let previous = makeMatch(
            id: "multi-correction",
            startDate: startDate,
            statusState: .inProgress,
            homeScore: "2",
            awayScore: "2"
        )
        let current = makeMatch(
            id: "multi-correction",
            startDate: startDate,
            statusState: .inProgress,
            homeScore: "1",
            awayScore: "1"
        )

        XCTAssertNil(CalendarMonitor.footballDisallowedGoalSide(from: previous, to: current))
    }

    func testDisallowedGoalTransitionIgnoresMultiGoalCorrections() {
        let previous = makeMatch(
            id: "multi-goal-correction",
            startDate: startDate,
            statusState: .inProgress,
            homeScore: "3",
            awayScore: "0"
        )
        let current = makeMatch(
            id: "multi-goal-correction",
            startDate: startDate,
            statusState: .inProgress,
            homeScore: "1",
            awayScore: "0"
        )

        XCTAssertNil(CalendarMonitor.footballDisallowedGoalSide(from: previous, to: current))
    }
}
