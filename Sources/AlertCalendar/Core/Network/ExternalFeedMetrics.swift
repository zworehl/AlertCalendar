import Foundation

struct ExternalFeedSourceMetrics: Equatable, Sendable {
    var checks = 0
    var networkRequests = 0
    var cacheHits = 0
    var coalescedRequests = 0
    var failures = 0
    var validationFailures = 0
    var hasUnresolvedFailure = false
    var lastAppliedDate: Date?
    var responseBytes = 0
    var lastStatusCode: Int?
    var lastCheckedDate: Date?
    var lastRequestDate: Date?
    var lastSuccessfulRequestDate: Date?
    var lastDataDate: Date?
    var lastRequestDuration: TimeInterval?
    var maximumRequestDuration: TimeInterval = 0
    var totalRequestDuration: TimeInterval = 0
    var recentRequestDurations: [TimeInterval] = []

    var averageRequestDuration: TimeInterval? {
        guard networkRequests > 0 else { return nil }
        return totalRequestDuration / Double(networkRequests)
    }

    mutating func recordRequestDuration(_ duration: TimeInterval) {
        let normalizedDuration = max(0, duration)
        lastRequestDuration = normalizedDuration
        maximumRequestDuration = max(maximumRequestDuration, normalizedDuration)
        totalRequestDuration += normalizedDuration
        recentRequestDurations.append(normalizedDuration)
        if recentRequestDurations.count > 64 {
            recentRequestDurations.removeFirst(recentRequestDurations.count - 64)
        }
    }
}

struct ExternalFeedDiagnostics: Equatable, Sendable {
    var sources: [String: ExternalFeedSourceMetrics] = [:]

    var networkRequests: Int { sources.values.reduce(0) { $0 + $1.networkRequests } }
    var cacheHits: Int { sources.values.reduce(0) { $0 + $1.cacheHits } }
    var failures: Int { sources.values.reduce(0) { $0 + $1.failures } }
    var responseBytes: Int { sources.values.reduce(0) { $0 + $1.responseBytes } }
    var medianRequestDuration: TimeInterval? { requestDurationPercentile(0.50) }
    var p95RequestDuration: TimeInterval? { requestDurationPercentile(0.95) }

    func latestCheckedDate(sourcePrefix: String) -> Date? {
        sources
            .filter { $0.key.hasPrefix(sourcePrefix) }
            .compactMap(\.value.lastCheckedDate)
            .max()
    }

    func latestSuccessfulRequestDate(sourcePrefix: String) -> Date? {
        sources
            .filter { $0.key.hasPrefix(sourcePrefix) }
            .compactMap(\.value.lastSuccessfulRequestDate)
            .max()
    }

    func latestDataDate(sourcePrefix: String) -> Date? {
        sources
            .filter { $0.key.hasPrefix(sourcePrefix) }
            .compactMap(\.value.lastDataDate)
            .max()
    }

    /// Oldest active source makes a partial refresh visible instead of letting
    /// the newest successful endpoint hide older data from another source.
    func oldestDataDate(sourcePrefix: String) -> Date? {
        let active = sources.filter {
            $0.key.hasPrefix(sourcePrefix) && !$0.key.hasSuffix(".stale") && !$0.key.hasSuffix(".negative")
        }.map(\.value)
        guard !active.isEmpty, active.allSatisfy({ $0.lastDataDate != nil }) else { return nil }
        return active.compactMap(\.lastDataDate).min()
    }

    func latestAppliedDate(sourcePrefix: String) -> Date? {
        sources.filter { $0.key.hasPrefix(sourcePrefix) }.compactMap(\.value.lastAppliedDate).max()
    }

    func oldestDataDate(sources keys: [String]) -> Date? {
        guard !keys.isEmpty, keys.allSatisfy({ sources[$0]?.lastDataDate != nil }) else { return nil }
        return keys.compactMap { sources[$0]?.lastDataDate }.min()
    }

    func hasUnresolvedFailure(sources keys: [String]) -> Bool {
        keys.contains { sources[$0]?.hasUnresolvedFailure == true }
    }

    func hasUnresolvedFailure(sourcePrefix: String) -> Bool {
        sources.contains { $0.key.hasPrefix(sourcePrefix) && $0.value.hasUnresolvedFailure }
    }

    private func requestDurationPercentile(_ percentile: Double) -> TimeInterval? {
        let values = sources.values.flatMap(\.recentRequestDurations).sorted()
        guard !values.isEmpty else { return nil }
        let boundedPercentile = min(max(percentile, 0), 1)
        let index = max(0, Int(ceil(Double(values.count) * boundedPercentile)) - 1)
        return values[min(max(index, 0), values.count - 1)]
    }
}

actor ExternalFeedMetrics {
    static let shared = ExternalFeedMetrics()

    private var sources: [String: ExternalFeedSourceMetrics] = [:]

    func recordCheck(source: String, at date: Date = Date()) {
        var metrics = sources[source, default: ExternalFeedSourceMetrics()]
        metrics.checks += 1
        metrics.lastCheckedDate = date
        sources[source] = metrics
    }

    func recordNetworkResponse(
        source: String,
        statusCode: Int,
        responseBytes: Int,
        duration: TimeInterval? = nil,
        at date: Date = Date()
    ) {
        var metrics = sources[source, default: ExternalFeedSourceMetrics()]
        metrics.networkRequests += 1
        metrics.responseBytes += max(0, responseBytes)
        metrics.lastStatusCode = statusCode
        metrics.lastCheckedDate = date
        metrics.lastRequestDate = date
        if (200...399).contains(statusCode) {
            metrics.lastSuccessfulRequestDate = date
        }
        if let duration {
            metrics.recordRequestDuration(duration)
        }
        if !(200...399).contains(statusCode) {
            metrics.failures += 1
            metrics.hasUnresolvedFailure = true
        }
        sources[source] = metrics
    }

    func recordTransportFailure(
        source: String,
        duration: TimeInterval? = nil,
        at date: Date = Date()
    ) {
        var metrics = sources[source, default: ExternalFeedSourceMetrics()]
        metrics.networkRequests += 1
        metrics.failures += 1
        metrics.hasUnresolvedFailure = true
        metrics.lastStatusCode = nil
        metrics.lastCheckedDate = date
        metrics.lastRequestDate = date
        if let duration {
            metrics.recordRequestDuration(duration)
        }
        sources[source] = metrics
    }

    func recordValidatedData(source: String, at date: Date = Date()) {
        var metrics = sources[source, default: ExternalFeedSourceMetrics()]
        metrics.lastDataDate = date
        metrics.hasUnresolvedFailure = false
        sources[source] = metrics
    }

    func recordDataFailure(source: String, validationFailed: Bool = false) {
        var metrics = sources[source, default: ExternalFeedSourceMetrics()]
        metrics.hasUnresolvedFailure = true
        if validationFailed { metrics.validationFailures += 1 }
        sources[source] = metrics
    }

    func recordAppliedData(source: String, at date: Date = Date()) {
        var metrics = sources[source, default: ExternalFeedSourceMetrics()]
        metrics.lastAppliedDate = date
        sources[source] = metrics
    }

    func recordCacheHit(source: String, dataDate: Date? = nil, at date: Date = Date()) {
        var metrics = sources[source, default: ExternalFeedSourceMetrics()]
        metrics.cacheHits += 1
        metrics.lastCheckedDate = date
        if let dataDate {
            metrics.lastDataDate = max(metrics.lastDataDate ?? dataDate, dataDate)
        }
        sources[source] = metrics
    }

    func recordCoalescedRequest(source: String) {
        var metrics = sources[source, default: ExternalFeedSourceMetrics()]
        metrics.coalescedRequests += 1
        sources[source] = metrics
    }

    func snapshot() -> ExternalFeedDiagnostics {
        ExternalFeedDiagnostics(sources: sources)
    }
}
