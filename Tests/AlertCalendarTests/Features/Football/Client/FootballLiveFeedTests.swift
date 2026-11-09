import Foundation
import XCTest
@testable import AlertCalendar

final class FootballLiveFeedTests: XCTestCase {
    func testLivePremierLeagueLoad() async throws {
        guard ProcessInfo.processInfo.environment["ALERTCALENDAR_LIVE_FOOTBALL_SMOKE"] == "1" else {
            throw XCTSkip("Opt-in ESPN smoke test; set ALERTCALENDAR_LIVE_FOOTBALL_SMOKE=1")
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 13, to: start))
        let client = FootballDataAPIClient()
        let result = try await client.fetchFixtureLoadResult(
            for: [.premierLeague],
            dateRangesByCompetitionSlug: ["eng.1": [FootballScoreboardDateRange(start: start, end: end)]],
            enrichTeams: false,
            forceRefresh: true
        )
        XCTAssertTrue(result.failures.isEmpty, result.warning ?? "Unexpected load failure")
        XCTAssertGreaterThan(result.availablePageCount, 0)
        print("Live ESPN Premier League: \(result.matches.count) matches, \(result.failures.count) failed ranges")
    }
}
