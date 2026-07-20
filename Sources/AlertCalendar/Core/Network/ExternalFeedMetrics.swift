import Foundation

struct ExternalFeedSourceMetrics: Equatable, Sendable {
    var networkRequests = 0
    var cacheHits = 0
    var coalescedRequests = 0
    var failures = 0
    var responseBytes = 0
    var lastStatusCode: Int?
    var lastRequestDate: Date?
}

struct ExternalFeedDiagnostics: Equatable, Sendable {
    var sources: [String: ExternalFeedSourceMetrics] = [:]

    var networkRequests: Int { sources.values.reduce(0) { $0 + $1.networkRequests } }
    var cacheHits: Int { sources.values.reduce(0) { $0 + $1.cacheHits } }
    var failures: Int { sources.values.reduce(0) { $0 + $1.failures } }
    var responseBytes: Int { sources.values.reduce(0) { $0 + $1.responseBytes } }
}

actor ExternalFeedMetrics {
    static let shared = ExternalFeedMetrics()

    private var sources: [String: ExternalFeedSourceMetrics] = [:]

    func recordNetworkResponse(
        source: String,
        statusCode: Int,
        responseBytes: Int,
        at date: Date = Date()
    ) {
        var metrics = sources[source, default: ExternalFeedSourceMetrics()]
        metrics.networkRequests += 1
        metrics.responseBytes += max(0, responseBytes)
        metrics.lastStatusCode = statusCode
        metrics.lastRequestDate = date
        if !(200...399).contains(statusCode) {
            metrics.failures += 1
        }
        sources[source] = metrics
    }

    func recordTransportFailure(source: String, at date: Date = Date()) {
        var metrics = sources[source, default: ExternalFeedSourceMetrics()]
        metrics.networkRequests += 1
        metrics.failures += 1
        metrics.lastStatusCode = nil
        metrics.lastRequestDate = date
        sources[source] = metrics
    }

    func recordCacheHit(source: String) {
        var metrics = sources[source, default: ExternalFeedSourceMetrics()]
        metrics.cacheHits += 1
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
