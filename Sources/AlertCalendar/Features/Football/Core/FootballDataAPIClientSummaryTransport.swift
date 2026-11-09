import Foundation

extension FootballDataAPIClient {
    static func validatedSummaryDictionary(from data: Data) throws -> [String: Any] {
        let root = try jsonDictionary(from: data)
        let hasObject = ["header", "boxscore"].contains { root[$0] is [String: Any] }
        let hasList = ["keyEvents", "plays", "scoringPlays", "rosters"].contains { root[$0] is [[String: Any]] }
        guard root["error"] == nil, hasObject || hasList else { throw ClientError.invalidResponse }
        return root
    }

    static func fetchSummaryRoot(
        url: URL,
        session: URLSession,
        transport: FootballDataAPITransport? = nil
    ) async throws -> [String: Any]? {
        guard let data = try await fetchSummaryData(url: url, session: session, transport: transport) else {
            return nil
        }
        do {
            let root = try validatedSummaryDictionary(from: data)
            await ExternalFeedMetrics.shared.recordValidatedData(source: "football.summary")
            return root
        } catch {
            await ExternalFeedMetrics.shared.recordDataFailure(source: "football.summary", validationFailed: true)
            throw error
        }
    }

    static func fetchSummaryData(
        url: URL,
        session: URLSession,
        transport: FootballDataAPITransport? = nil
    ) async throws -> Data? {
        // App-level caches control freshness; URLCache must not extend their TTL.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = Self.requestTimeout
        let requestStartedAt = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.apiData(for: request, session: session, transport: transport)
        } catch {
            if error is ClientError || error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            await ExternalFeedMetrics.shared.recordTransportFailure(
                source: "football.summary",
                duration: Date().timeIntervalSince(requestStartedAt)
            )
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        await ExternalFeedMetrics.shared.recordNetworkResponse(
            source: "football.summary",
            statusCode: http.statusCode,
            responseBytes: data.count,
            duration: Date().timeIntervalSince(requestStartedAt)
        )
        if http.statusCode == 429 {
            throw ClientError.rateLimited(until: Self.rateLimitRetryDate(
                header: http.value(forHTTPHeaderField: "Retry-After"), now: Date()
            ))
        }
        guard (200...299).contains(http.statusCode) else {
            throw ClientError.unsuccessfulResponse(statusCode: http.statusCode)
        }
        return data
    }

}
