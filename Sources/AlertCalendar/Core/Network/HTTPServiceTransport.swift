import Foundation

enum HTTPServiceRetryError: Error, Equatable, Sendable {
    case deferred(statusCode: Int?, until: Date)
}

enum HTTPServiceRetryPolicy {
    static func retryDate(statusCode: Int, retryAfter: String?, now: Date, failures: Int = 1) -> Date {
        let fallback: TimeInterval
        switch statusCode {
        case 403: fallback = 300
        case 429: fallback = 60
        case 500...599: fallback = min(3_600, 60 * pow(2, Double(min(max(failures - 1, 0), 6))))
        default: fallback = 60
        }
        guard let retryAfter else { return now.addingTimeInterval(fallback) }
        if let seconds = TimeInterval(retryAfter), seconds.isFinite {
            return now.addingTimeInterval(max(fallback, seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return max(now.addingTimeInterval(fallback), formatter.date(from: retryAfter) ?? now)
    }
}

/// A shared request budget for each integration. Provider waiting periods apply
/// across endpoints and remain in force when the user requests a manual refresh.
actor HTTPServiceTransport {
    private struct Cooldown {
        let statusCode: Int?
        let until: Date
    }
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    private let session: URLSession
    private let maximumConcurrentRequests: Int
    private let now: @Sendable () -> Date
    private var cooldowns: [String: Cooldown] = [:]
    private var failureCounts: [String: Int] = [:]
    private var activeRequests = 0
    private var waiters: [Waiter] = []

    init(session: URLSession, maximumConcurrentRequests: Int = 4, now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.maximumConcurrentRequests = max(1, maximumConcurrentRequests)
        self.now = now
    }

    func data(for request: URLRequest, at date: Date? = nil) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        let host = request.url?.host?.lowercased() ?? ""
        let resource = request.url?.absoluteString ?? host
        try check(keys: [host, resource], at: date ?? now())
        try await acquireSlot()
        defer { releaseSlot() }
        try Task.checkCancellation()
        try check(keys: [host, resource], at: date ?? now())
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                if !(200...399).contains(http.statusCode) {
                    failureCounts[host, default: 0] += 1
                    let key = http.statusCode == 403 || http.statusCode == 429 || http.statusCode >= 500 ? host : resource
                    pause(key, cooldown: Cooldown(statusCode: http.statusCode, until: HTTPServiceRetryPolicy.retryDate(
                        statusCode: http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After"),
                        now: date ?? now(), failures: failureCounts[host] ?? 1
                    )))
                } else {
                    failureCounts[host] = nil
                }
            }
            return (data, response)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            pause(host, cooldown: Cooldown(statusCode: nil, until: (date ?? now()).addingTimeInterval(15)))
            throw error
        }
    }

    func resumeAfterConnectivityRecovery() {
        cooldowns = cooldowns.filter { $0.value.statusCode != nil }
    }

    private func check(keys: [String], at current: Date) throws {
        for key in keys {
            guard let value = cooldowns[key] else { continue }
            if current >= value.until { cooldowns[key] = nil }
            else { throw HTTPServiceRetryError.deferred(statusCode: value.statusCode, until: value.until) }
        }
    }

    private func pause(_ key: String, cooldown: Cooldown) {
        if let existing = cooldowns[key], existing.until >= cooldown.until { return }
        cooldowns[key] = cooldown
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
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiters.append(Waiter(id: id, continuation: continuation)) }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func releaseSlot() {
        if waiters.isEmpty { activeRequests -= 1 }
        else { waiters.removeFirst().continuation.resume() }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
