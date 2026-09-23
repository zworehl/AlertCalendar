import XCTest
@testable import AlertCalendar

final class FootballGoalScorersAvailabilityTests: FootballDataAPIClientTestCase {
    func testScoreWithoutGoalDetailsReturnsUnavailableInsteadOfInventingAScorer() async throws {
        let match = makeMatch(id: "no-coverage", statusState: .inProgress, homeScore: "0", awayScore: "1")
        let session = makeMockSession { request in
            try self.jsonResponse(for: request, body: ["header": ["id": match.id], "boxscore": ["teams": []]])
        }
        let result = try await FootballDataAPIClient(session: session).fetchGoalScorers(for: match, enrichCountries: false)
        XCTAssertNil(result)
    }

    func testScorerNamesCanBeShownWithoutWaitingForNationalityRequests() async throws {
        let match = FootballTestData.match(id: "quick-scorer", statusState: .inProgress, homeScore: "0", awayScore: "1")
        var requestedHosts: [String] = []
        let session = makeMockSession { request in
            requestedHosts.append(request.url?.host ?? "")
            return try self.jsonResponse(for: request, body: ["keyEvents": [[
                "scoringPlay": true,
                "team": ["id": "132"],
                "clock": ["displayValue": "18'"],
                "participants": [["athlete": ["id": "142200", "displayName": "Harry Kane"]]],
                "type": ["text": "Goal"],
            ]]])
        }
        let result = try await FootballDataAPIClient(session: session).fetchGoalScorers(for: match, enrichCountries: false)
        XCTAssertEqual(result?.away.first?.name, "Harry Kane")
        XCTAssertEqual(result?.away.first?.minute, "18'")
        XCTAssertEqual(requestedHosts, ["site.api.espn.com"])
    }

    @MainActor
    func testMinuteChangesDoNotRestartScorerLoadingButGoalsAndFullTimeDo() {
        func match(minute: String, score: String = "1", state: FootballFixtureStatusState = .inProgress) -> FootballFixtureMatch {
            FootballTestData.match(id: "stable-request", statusState: state, statusText: minute, homeScore: "0", awayScore: score)
        }
        let initial = FootballGoalScorersSection.requestKey(for: match(minute: "45'+2'"))
        XCTAssertEqual(initial, FootballGoalScorersSection.requestKey(for: match(minute: "HT")))
        XCTAssertEqual(initial, FootballGoalScorersSection.requestKey(for: match(minute: "46'")))
        XCTAssertNotEqual(initial, FootballGoalScorersSection.requestKey(for: match(minute: "46'", score: "2")))
        XCTAssertNotEqual(initial, FootballGoalScorersSection.requestKey(for: match(minute: "FT", state: .finished)))
    }
}
