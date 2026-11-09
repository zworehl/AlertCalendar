import Foundation
import XCTest
@testable import AlertCalendar

final class FootballScoreRefreshPresentationTests: AlertCalendarModelTestCase {
    func testFootballHeartbeatPresentationReplacesCachedScoreAndClock() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let start = now.addingTimeInterval(-60 * 60)
        let oldMatch = makeFootballMatch(
            id: "match", startDate: start, actualStartDate: nil,
            statusState: .inProgress, statusText: "15'"
        )
        let newMatch = makeFootballMatch(
            id: "match", startDate: start, actualStartDate: nil,
            statusState: .inProgress, statusText: "60'", homeScore: "3", awayScore: "0"
        )
        let item = makeFootballUpcomingItem(oldMatch)
        let display = FootballFixtureFormatter.menuBarDisplay(
            for: newMatch, competitionLocalLogoURL: nil, homeLocalLogoURL: nil, awayLocalLogoURL: nil
        )
        let updated = CalendarMonitor.footballItem(item, updatingWith: newMatch, menuBarDisplay: display, now: now)

        XCTAssertEqual(updated.footballMatch?.homeScore, "3")
        XCTAssertEqual(updated.footballMatch?.statusText, "60'")
        XCTAssertEqual(updated.footballMenuBarDisplay, display)
        XCTAssertEqual(updated.title, FootballFixtureFormatter.calendarTitle(for: newMatch))
        XCTAssertEqual(updated.id, item.id)
        XCTAssertEqual(updated.notificationKey, item.notificationKey)
        XCTAssertEqual(updated.calendarID, item.calendarID)
        XCTAssertEqual(updated.calendarName, item.calendarName)
        XCTAssertEqual(updated.calendarColor, item.calendarColor)
        XCTAssertEqual(updated.descriptionText, item.descriptionText)
    }

    func testFinalScorePresentationUsesActualEndDate() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let start = now.addingTimeInterval(-2 * 60 * 60)
        let oldMatch = makeFootballMatch(
            id: "match", startDate: start, actualStartDate: nil,
            statusState: .inProgress, statusText: "90'"
        )
        let end = now.addingTimeInterval(-60)
        let final = FootballTestData.friendlyMatch(
            id: "match", startDate: start, actualEndDate: end,
            statusState: .finished, statusText: "FT", homeScore: "0", awayScore: "3"
        )
        let updated = CalendarMonitor.footballItem(
            makeFootballUpcomingItem(oldMatch), updatingWith: final,
            menuBarDisplay: FootballFixtureFormatter.menuBarDisplay(
                for: final, competitionLocalLogoURL: nil, homeLocalLogoURL: nil, awayLocalLogoURL: nil
            ), now: now
        )
        XCTAssertEqual(updated.footballMatch?.statusState, .finished)
        XCTAssertEqual(updated.footballMatch?.awayScore, "3")
        XCTAssertEqual(updated.endDate, end)
    }
}
