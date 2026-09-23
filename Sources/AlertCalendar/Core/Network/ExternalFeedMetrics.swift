import Foundation

struct ExternalFeedSourceMetrics: Equatable, Sendable {
    var checks = 0
    var networkRequests = 0
    var cacheHits = 0
    var coalescedRequests = 0
    var failures = 0
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
            metrics.lastDataDate = date
        }
        if let duration {
            metrics.recordRequestDuration(duration)
        }
        if !(200...399).contains(statusCode) {
            metrics.failures += 1
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
        metrics.lastStatusCode = nil
        metrics.lastCheckedDate = date
        metrics.lastRequestDate = date
        if let duration {
            metrics.recordRequestDuration(duration)
        }
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
