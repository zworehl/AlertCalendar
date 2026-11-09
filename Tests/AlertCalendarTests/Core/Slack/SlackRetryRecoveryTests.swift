import Foundation
import XCTest
@testable import AlertCalendar

final class SlackRetryRecoveryTests: IntegrationHTTPTestCase {
    func testOfflineCooldownDoesNotInventAnHTTPStatus() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let log = IntegrationRequestLog()
        let client = SlackAPIClient(session: session { _ in
            log.record("calls")
            throw URLError(.notConnectedToInternet)
        }, clock: { now })
        do { _ = try await client.connectUserToken("xoxp-test-user-token"); XCTFail("Expected offline") }
        catch let error as URLError { XCTAssertEqual(error.code, .notConnectedToInternet) }
        do {
            _ = try await client.connectUserToken("xoxp-test-user-token")
            XCTFail("Expected a deferred offline attempt")
        } catch SlackAPIError.retryDeferred(let status, _) {
            XCTAssertNil(status)
        }
        XCTAssertEqual(log.count("calls"), 1)
    }

    func testRateLimitedConnectionRetainsDeadlineAndDoesNotIssueAnotherRequest() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let log = IntegrationRequestLog()
        let client = SlackAPIClient(session: session { request in
            log.record("calls")
            return self.reply(request, status: 429, headers: ["Retry-After": "600"])
        }, clock: { now })
        for _ in 0..<2 {
            do {
                _ = try await client.connectUserToken("xoxp-test-user-token")
                XCTFail("Expected the provider waiting period")
            } catch SlackAPIError.retryDeferred(let status, let until) {
                XCTAssertEqual(status, 429)
                XCTAssertEqual(until, now.addingTimeInterval(600))
            }
        }
        XCTAssertEqual(log.count("calls"), 1)
    }
}
