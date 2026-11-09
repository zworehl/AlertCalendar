import Foundation
import XCTest
@testable import AlertCalendar

final class HTTPServiceTransportTests: IntegrationHTTPTestCase {
    func testRetryAfterBlocksDifferentResourcesEvenForARepeatedManualRequest() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let log = IntegrationRequestLog()
        let session = session { request in
            let attempt = log.record("all")
            return self.reply(request, status: attempt == 1 ? 429 : 200, headers: ["Retry-After": "600"])
        }
        let transport = HTTPServiceTransport(session: session)
        let first = URLRequest(url: URL(string: "https://provider.test/one")!)
        let second = URLRequest(url: URL(string: "https://provider.test/two")!)
        let (_, response) = try await transport.data(for: first, at: now)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 429)
        for seconds in [1.0, 300, 599] {
            do {
                _ = try await transport.data(for: second, at: now.addingTimeInterval(seconds))
                XCTFail("The provider's deadline must cover other endpoints")
            } catch HTTPServiceRetryError.deferred(let status, let until) {
                XCTAssertEqual(status, 429)
                XCTAssertEqual(until, now.addingTimeInterval(600))
            }
        }
        XCTAssertEqual(log.count("all"), 1)
        _ = try await transport.data(for: second, at: now.addingTimeInterval(600))
        XCTAssertEqual(log.count("all"), 2)
    }

    func testOfflineFailureIsBoundedAndAnotherHostCanStillRefresh() async throws {
        let log = IntegrationRequestLog()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let transport = HTTPServiceTransport(session: session { request in
            let count = log.record(request.url!.host!)
            if request.url?.host == "offline.test", count == 1 { throw URLError(.notConnectedToInternet) }
            return self.reply(request)
        })
        let offline = URLRequest(url: URL(string: "https://offline.test/feed")!)
        do { _ = try await transport.data(for: offline, at: now); XCTFail("Expected offline") }
        catch let error as URLError { XCTAssertEqual(error.code, .notConnectedToInternet) }
        do { _ = try await transport.data(for: offline, at: now.addingTimeInterval(1)); XCTFail("Expected cooldown") }
        catch HTTPServiceRetryError.deferred(let status, _) { XCTAssertNil(status) }
        _ = try await transport.data(for: URLRequest(url: URL(string: "https://healthy.test/feed")!), at: now)
        _ = try await transport.data(for: offline, at: now.addingTimeInterval(15))
        XCTAssertEqual(log.count("offline.test"), 2)
        XCTAssertEqual(log.count("healthy.test"), 1)
    }

    func testRetryPolicyAcceptsHTTPDateAndRejectsInvalidOrShortDeadlines() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(HTTPServiceRetryPolicy.retryDate(statusCode: 429, retryAfter: "Thu, 01 Jan 1970 00:10:00 GMT", now: now), now.addingTimeInterval(600))
        XCTAssertEqual(HTTPServiceRetryPolicy.retryDate(statusCode: 429, retryAfter: "-5", now: now), now.addingTimeInterval(60))
        XCTAssertEqual(HTTPServiceRetryPolicy.retryDate(statusCode: 503, retryAfter: "nonsense", now: now), now.addingTimeInterval(60))
    }
}
