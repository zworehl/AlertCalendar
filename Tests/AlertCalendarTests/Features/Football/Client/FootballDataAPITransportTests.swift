import Foundation
import XCTest
@testable import AlertCalendar

private final class FootballTransportMockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var body = "{\"events\":[]}"
        var delay: TimeInterval = 0
        var finished: @Sendable () -> Void = {}
    }

    nonisolated(unsafe) static var handler: ((URLRequest) -> Reply)?
    private let lock = NSLock()
    private var stopped = false
    private var finished: (@Sendable () -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let reply = Self.handler?(request), let url = request.url else { return }
        lock.withLock { finished = reply.finished }
        DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [self] in
            guard !lock.withLock({ stopped }) else { return }
            let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
            finishRequest()
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        lock.withLock { stopped = true }
        finishRequest()
    }

    private func finishRequest() {
        let completion = lock.withLock { let value = finished; finished = nil; return value }
        completion?()
    }
}

private final class FootballTransportTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private(set) var maximum = 0
    private(set) var starts: [Date] = []
    private var date = Date(timeIntervalSince1970: 1_800_000_000)

    func started() {
        lock.withLock {
            active += 1
            maximum = max(maximum, active)
            starts.append(Date())
        }
    }
    func finished() { lock.withLock { active -= 1 } }
    func count() -> Int { lock.withLock { starts.count } }
    func peak() -> Int { lock.withLock { maximum } }
    func startDates() -> [Date] { lock.withLock { starts } }
    func now() -> Date { lock.withLock { date } }
    func advance(_ interval: TimeInterval) { lock.withLock { date += interval } }
}

final class FootballDataAPITransportTests: XCTestCase, @unchecked Sendable {
    override func tearDown() {
        FootballTransportMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testConcurrentPagesShareTwoSlots() async throws {
        let state = FootballTransportTestState()
        let session = makeSession { _ in
            state.started()
            return .init(delay: 0.05, finished: { state.finished() })
        }
        let transport = FootballDataAPITransport(session: session, minimumStartInterval: 0)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for page in 0..<12 {
                group.addTask { _ = try await transport.data(for: self.request("page-\(page)")) }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(state.count(), 12)
        XCTAssertEqual(state.peak(), 2)
    }

    func testRequestStartsArePacedAcrossConcurrentCalls() async throws {
        let state = FootballTransportTestState()
        let session = makeSession { _ in
            state.started()
            return .init(finished: { state.finished() })
        }
        let transport = FootballDataAPITransport(session: session, minimumStartInterval: 0.04)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for page in 0..<4 {
                group.addTask { _ = try await transport.data(for: self.request("page-\(page)")) }
            }
            try await group.waitForAll()
        }
        let starts = state.startDates()
        XCTAssertEqual(starts.count, 4)
        for index in 1..<starts.count {
            XCTAssertGreaterThanOrEqual(starts[index].timeIntervalSince(starts[index - 1]), 0.025)
        }
    }

    func testForbiddenHostStopsDifferentURLsAndRecoversAfterCooldown() async throws {
        let state = FootballTransportTestState()
        let session = makeSession { request in
            state.started()
            let denied = request.url?.host == "site.api.espn.com" && state.now().timeIntervalSince1970 < 1_800_000_300
            return .init(status: denied ? 403 : 200, finished: { state.finished() })
        }
        let transport = FootballDataAPITransport(session: session, minimumStartInterval: 0, now: { state.now() })
        let (_, response) = try await transport.data(for: request("first"))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 403)
        for page in 0..<40 {
            do {
                _ = try await transport.data(for: request("different-\(page)"))
                XCTFail("A denied host must not be probed for each URL")
            } catch FootballDataAPIClient.ClientError.unsuccessfulResponse(let status) {
                XCTAssertEqual(status, 403)
            }
        }
        XCTAssertEqual(state.count(), 1)
        let (_, core) = try await transport.data(for: request("team", host: "sports.core.api.espn.com"))
        XCTAssertEqual((core as? HTTPURLResponse)?.statusCode, 200)
        state.advance(300)
        let (_, recovered) = try await transport.data(for: request("recovered"))
        XCTAssertEqual((recovered as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(state.count(), 3)
    }

    func testRetryAfterAppliesAcrossURLsUntilItsDeadline() async throws {
        let state = FootballTransportTestState()
        let session = makeSession { _ in
            state.started()
            return .init(status: state.count() == 1 ? 429 : 200, headers: ["Retry-After": "600"], finished: { state.finished() })
        }
        let transport = FootballDataAPITransport(session: session, minimumStartInterval: 0, now: { state.now() })
        _ = try await transport.data(for: request("limited"))
        state.advance(599)
        do {
            _ = try await transport.data(for: request("new-url"))
            XCTFail("Retry-After must cover other URLs")
        } catch FootballDataAPIClient.ClientError.rateLimited(let until) {
            XCTAssertEqual(until, Date(timeIntervalSince1970: 1_800_000_600))
        }
        XCTAssertEqual(state.count(), 1)
        state.advance(1)
        let (_, recovered) = try await transport.data(for: request("retry"))
        XCTAssertEqual((recovered as? HTTPURLResponse)?.statusCode, 200)
    }

    func testConcurrentDenialsCannotShortenLongerCooldown() async throws {
        let state = FootballTransportTestState()
        let session = makeSession { request in
            state.started()
            return request.url?.lastPathComponent == "longer"
                ? .init(status: 429, headers: ["Retry-After": "600"], delay: 0.02, finished: { state.finished() })
                : .init(status: 403, delay: 0.05, finished: { state.finished() })
        }
        let transport = FootballDataAPITransport(session: session, minimumStartInterval: 0, now: { state.now() })
        async let longer = transport.data(for: request("longer"))
        async let shorter = transport.data(for: request("shorter"))
        _ = try await (longer, shorter)
        state.advance(301)
        do {
            _ = try await transport.data(for: request("retry"))
            XCTFail("A later 403 must not shorten Retry-After")
        } catch FootballDataAPIClient.ClientError.rateLimited(let until) {
            XCTAssertEqual(until, Date(timeIntervalSince1970: 1_800_000_600))
        }
        XCTAssertEqual(state.count(), 2)
    }

    func testCancellationWhileQueuedDoesNotLeakASlot() async throws {
        let began = expectation(description: "First request began")
        let state = FootballTransportTestState()
        let session = makeSession { _ in
            state.started()
            if state.count() == 1 { began.fulfill() }
            return .init(delay: 0.1, finished: { state.finished() })
        }
        let transport = FootballDataAPITransport(session: session, maximumConcurrentRequests: 1, minimumStartInterval: 0)
        let first = Task { try await transport.data(for: request("first")) }
        await fulfillment(of: [began], timeout: 2)
        let cancelled = Task { try await transport.data(for: request("cancelled")) }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            XCTFail("A cancelled waiter must return")
        } catch is CancellationError {}
        _ = try await first.value
        _ = try await transport.data(for: request("after-cancellation"))
        XCTAssertEqual(state.count(), 2)
        XCTAssertEqual(state.peak(), 1)
    }

    func testClientSharesCooldownAcrossScoreboardSummaryTeamsAndAthletes() async throws {
        let state = FootballTransportTestState()
        let session = makeSession { _ in
            state.started()
            return .init(status: 403, finished: { state.finished() })
        }
        let client = FootballDataAPIClient(session: session)
        do {
            _ = try await client.scoreboardMatchesPage(
                url: request("scoreboard").url!, slug: "eng.1", competitionName: "Premier League", forceRefresh: true
            )
            XCTFail("The first rejected request must report 403")
        } catch FootballDataAPIClient.ClientError.unsuccessfulResponse(let status) {
            XCTAssertEqual(status, 403)
        }
        let match = FootballTestData.friendlyMatch(id: "summary", startDate: Date(), statusState: .inProgress)
        for _ in 0..<2 {
            do {
                try await client.requestSummaryForTransportTest(url: request("summary").url!, match: match)
                XCTFail("Summary cooldown must preserve the provider error")
            } catch FootballDataAPIClient.ClientError.unsuccessfulResponse(let status) {
                XCTAssertEqual(status, 403)
            }
        }
        _ = await client.enrichTeams(in: [match])
        _ = await client.fetchAthleteCountryName(athleteID: "different-athlete")
        XCTAssertEqual(state.count(), 2, "Only the first request to each API host should reach the network")
    }

    private func request(_ path: String, host: String = "site.api.espn.com") -> URLRequest {
        URLRequest(url: URL(string: "https://\(host)/\(path)")!)
    }

    private func makeSession(handler: @escaping (URLRequest) -> FootballTransportMockURLProtocol.Reply) -> URLSession {
        FootballTransportMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FootballTransportMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private extension FootballDataAPIClient {
    func requestSummaryForTransportTest(url: URL, match: FootballFixtureMatch) async throws {
        _ = try await summaryRoot(url: url, match: match, forceRefresh: true)
    }
}
