import Foundation
import XCTest
@testable import AlertCalendar

final class FootballVenueBackfillTests: FootballDataAPIClientTestCase {
    func testScheduledMatchGetsVenueFromSummaryBeforeKickoffWindow() async throws {
        let match = FootballTestData.match(id: "future-match", startDate: Date().addingTimeInterval(7 * 86_400), statusState: .scheduled)
        let session = makeMockSession { request in
            try self.jsonResponse(for: request, body: [
                "header": ["competitions": [[
                    "status": ["type": ["state": "pre", "completed": false, "description": "Scheduled"]],
                    "competitors": [["homeAway": "home", "score": "0"], ["homeAway": "away", "score": "0"]]
                ]]],
                "gameInfo": ["venue": ["fullName": "Test Stadium", "address": ["city": "Test City"]]]
            ])
        }
        let client = FootballDataAPIClient(session: session)
        let selection = CalendarMonitor.footballManagedMatchIDsNeedingVenueBackfill(
            [match], trackedMatchIDs: [match.id], cachedMatchesByID: [:]
        )
        let refreshed = await client.refreshStatusesIfNeeded(for: [match], forceSummaryForMatchIDs: selection)
        XCTAssertEqual(refreshed.first?.locationText, "Test Stadium, Test City")
        XCTAssertEqual(refreshed.first?.startDate, match.startDate)
        XCTAssertEqual(refreshed.first?.statusState, .scheduled)
    }
}
