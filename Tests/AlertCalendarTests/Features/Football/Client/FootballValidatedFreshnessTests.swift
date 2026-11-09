import Foundation
import XCTest
@testable import AlertCalendar

final class FootballValidatedFreshnessTests: FootballDataAPIClientTestCase {
    func testSummaryRejectsReadableJSONThatIsAnErrorEnvelope() throws {
        XCTAssertThrowsError(try FootballDataAPIClient.validatedSummaryDictionary(from: Data("{\"error\":\"maintenance\"}".utf8)))
        XCTAssertThrowsError(try FootballDataAPIClient.validatedSummaryDictionary(from: Data("{}".utf8)))
        XCTAssertNoThrow(try FootballDataAPIClient.validatedSummaryDictionary(from: Data("{\"header\":{\"id\":\"match\"}}".utf8)))
    }

    func testInvalidHTTP200DoesNotAdvanceScoreboardDataFreshness() async throws {
        let slug = "validation-\(UUID().uuidString)"
        let client = FootballDataAPIClient(session: makeMockSession { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("not JSON".utf8))
        })
        do {
            _ = try await client.scoreboardMatchesPage(url: URL(string: "https://provider.test/scoreboard")!, slug: slug, competitionName: "Test")
            XCTFail("Expected invalid data")
        } catch { }
        let metrics = await ExternalFeedMetrics.shared.snapshot()
        let source = metrics.sources["football.scoreboard.\(slug)"]
        XCTAssertNotNil(source?.lastSuccessfulRequestDate)
        XCTAssertNil(source?.lastDataDate)
        XCTAssertTrue(source?.hasUnresolvedFailure == true)
        XCTAssertEqual(source?.validationFailures, 1)
    }
}
