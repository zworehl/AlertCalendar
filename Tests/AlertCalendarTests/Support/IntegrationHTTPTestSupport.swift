import Foundation
import XCTest

final class IntegrationHTTPMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badURL) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class IntegrationRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    @discardableResult func record(_ key: String) -> Int {
        lock.withLock { counts[key, default: 0] += 1; return counts[key, default: 0] }
    }
    func count(_ key: String) -> Int { lock.withLock { counts[key, default: 0] } }
}

class IntegrationHTTPTestCase: XCTestCase {
    override func tearDown() {
        IntegrationHTTPMockURLProtocol.handler = nil
        super.tearDown()
    }
    func session(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
        IntegrationHTTPMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IntegrationHTTPMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        addTeardownBlock { session.invalidateAndCancel() }
        return session
    }
    func reply(_ request: URLRequest, status: Int = 200, body: String = "{}", headers: [String: String] = [:]) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, Data(body.utf8))
    }
}
