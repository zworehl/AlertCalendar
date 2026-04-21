import Foundation
import XCTest
@testable import AlertCalendar

private final class FootballDataAPIClientMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            XCTFail("Missing request handler")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

class FootballDataAPIClientTestCase: XCTestCase {
    override func tearDown() {
        FootballDataAPIClientMockURLProtocol.requestHandler = nil
        super.tearDown()
    }
    func makeMatch(
        id: String,
        statusState: FootballFixtureStatusState,
        homeScore: String,
        awayScore: String
    ) -> FootballFixtureMatch {
        FootballTestData.friendlyMatch(
            id: id,
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: statusState,
            statusText: "55'",
            homeScore: homeScore,
            awayScore: awayScore
        )
    }
    func makeMockSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FootballDataAPIClientMockURLProtocol.self]
        FootballDataAPIClientMockURLProtocol.requestHandler = handler
        return URLSession(configuration: configuration)
    }
    func jsonResponse(
        for request: URLRequest,
        body: [String: Any]
    ) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )
        return (response, data)
    }
}
