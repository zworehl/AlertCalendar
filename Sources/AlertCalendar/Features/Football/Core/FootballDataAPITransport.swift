import Foundation

/// All ESPN API routes share a small request budget. A denied host is paused
/// across URLs so a large date-window refresh cannot keep probing every day.
actor FootballDataAPITransport {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private struct HostCooldown {
        let until: Date
        let error: FootballDataAPIClient.ClientError
    }

    private let session: URLSession
    private let maximumConcurrentRequests: Int
    private let minimumStartInterval: TimeInterval
    private let deniedRetryInterval: TimeInterval
    private let now: @Sendable () -> Date
    private var activeRequests = 0
    private var waiters: [Waiter] = []
    private var nextStart = ContinuousClock.now
    private var hostCooldowns: [String: HostCooldown] = [:]

    init(
        session: URLSession,
        maximumConcurrentRequests: Int = 2,
        minimumStartInterval: TimeInterval = 0.25,
        deniedRetryInterval: TimeInterval = 5 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.session = session
        self.maximumConcurrentRequests = max(1, maximumConcurrentRequests)
        self.minimumStartInterval = max(0, minimumStartInterval)
        self.deniedRetryInterval = max(0, deniedRetryInterval)
        self.now = now
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        let host = request.url?.host?.lowercased() ?? ""
        try checkHost(host)
        try await acquireSlot()
        defer { releaseSlot() }
        try Task.checkCancellation()
        try checkHost(host)

        while ContinuousClock.now < nextStart {
            try await Task.sleep(until: nextStart, clock: .continuous)
            try Task.checkCancellation()
            // Another request may have started or paused the host while this one waited.
            try checkHost(host)
        }
        nextStart = ContinuousClock.now.advanced(by: .seconds(minimumStartInterval))
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 403 {
                pauseHost(host, cooldown: HostCooldown(
                    until: now().addingTimeInterval(deniedRetryInterval),
                    error: .unsuccessfulResponse(statusCode: 403)
                ))
            } else if http.statusCode == 429 {
                let until = FootballDataAPIClient.rateLimitRetryDate(
                    header: http.value(forHTTPHeaderField: "Retry-After"), now: now()
                )
                pauseHost(host, cooldown: HostCooldown(until: until, error: .rateLimited(until: until)))
            }
        }
        return (data, response)
    }

    private func pauseHost(_ host: String, cooldown: HostCooldown) {
        if let existing = hostCooldowns[host], existing.until >= cooldown.until { return }
        hostCooldowns[host] = cooldown
    }

    private func checkHost(_ host: String) throws {
        guard let cooldown = hostCooldowns[host] else { return }
        guard now() >= cooldown.until else { throw cooldown.error }
        hostCooldowns[host] = nil
    }

    private func acquireSlot() async throws {
        try Task.checkCancellation()
        if activeRequests < maximumConcurrentRequests, waiters.isEmpty {
            activeRequests += 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func releaseSlot() {
        if waiters.isEmpty {
            activeRequests -= 1
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

extension FootballDataAPIClient {
    static func apiData(
        for request: URLRequest, session: URLSession, transport: FootballDataAPITransport?
    ) async throws -> (Data, URLResponse) {
        if let transport { return try await transport.data(for: request) }
        return try await session.data(for: request)
    }
}
