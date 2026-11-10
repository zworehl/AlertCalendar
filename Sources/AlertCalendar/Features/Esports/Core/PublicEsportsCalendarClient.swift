import Foundation

/// The publisher explicitly offers this ICS subscription without an account.
/// Canonical PandaScore IDs come from its published UIDs, never inferred names.
actor PublicEsportsCalendarClient: EsportsProviding {
    static let sourceURL = URL(string: "https://www.esport-calendar.com/")!
    static let attribution = "Source: Esports Calendar · Data: PandaScore"
    private let transport: HTTPServiceTransport
    private let now: @Sendable () -> Date
    private let hourlyRequestLimit: Int
    private var requestDates: [Date] = []

    init(session: URLSession = AlertCalendarHTTPClient.shared, transport: HTTPServiceTransport? = nil,
         hourlyRequestLimit: Int = 24, now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport ?? HTTPServiceTransport(session: session, maximumConcurrentRequests: 2, now: now)
        self.hourlyRequestLimit = min(max(1, hourlyRequestLimit), 120)
        self.now = now
    }

    func load(game: EsportsGame, from: Date, to: Date, trackedIDs: [Int] = []) async throws -> EsportsLoadResult {
        try Task.checkCancellation()
        guard let slug = Self.slug(for: game) else { throw EsportsFeedError.unsupportedGame }
        guard from.timeIntervalSince1970.isFinite, to.timeIntervalSince1970.isFinite,
              from < to, to.timeIntervalSince(from) <= 550 * 86_400 else { throw EsportsFeedError.invalidWindow }
        let fetchedAt = now()
        requestDates.removeAll { fetchedAt.timeIntervalSince($0) >= 3_600 }
        guard requestDates.count < hourlyRequestLimit else {
            throw EsportsFeedError.requestBudget(until: (requestDates.first ?? fetchedAt).addingTimeInterval(3_600))
        }
        requestDates.append(fetchedAt)
        var components = URLComponents(string: "https://www.esport-calendar.com/calendar.ics")!
        components.queryItems = [URLQueryItem(name: "games", value: slug)]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.httpShouldHandleCookies = false
        request.setValue("text/calendar", forHTTPHeaderField: "Accept")
        let source = "esports.\(game.rawValue)"
        await ExternalFeedMetrics.shared.recordCheck(source: source, at: fetchedAt)
        let started = Date()
        do {
            let (data, response) = try await transport.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw EsportsFeedError.invalidResponse }
            await ExternalFeedMetrics.shared.recordNetworkResponse(source: source, statusCode: http.statusCode,
                responseBytes: data.count, duration: Date().timeIntervalSince(started), at: fetchedAt)
            guard let url = http.url, Self.accepts(url: url, slug: slug) else { throw EsportsFeedError.invalidResponse }
            switch http.statusCode {
            case 200: break
            case 401, 403: throw EsportsFeedError.unavailable
            case 429: throw EsportsFeedError.rateLimited(until: HTTPServiceRetryPolicy.retryDate(statusCode: 429,
                retryAfter: http.value(forHTTPHeaderField: "Retry-After"), now: fetchedAt))
            default: throw EsportsFeedError.unexpectedStatus(http.statusCode)
            }
            let parsed = try PublicEsportsCalendarParser.parse(data, game: game, from: from, to: to,
                trackedIDs: trackedIDs, fetchedAt: fetchedAt)
            let issues: [EsportsLoadIssue] = parsed.rejectedEvents == 0 ? [] : [.init(kind: .invalidPayload)]
            if issues.isEmpty { await ExternalFeedMetrics.shared.recordValidatedData(source: source, at: fetchedAt) }
            else { await ExternalFeedMetrics.shared.recordDataFailure(source: source, validationFailed: true) }
            return EsportsLoadResult(matches: parsed.matches, isComplete: issues.isEmpty, issues: issues, fetchedAt: fetchedAt)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if let error = error as? EsportsFeedError {
                await ExternalFeedMetrics.shared.recordDataFailure(source: source, validationFailed: error == .invalidPayload)
                throw error
            }
            if case HTTPServiceRetryError.deferred(let status, let until) = error {
                throw EsportsFeedError.retryDeferred(statusCode: status, until: until)
            }
            await ExternalFeedMetrics.shared.recordTransportFailure(source: source,
                duration: Date().timeIntervalSince(started), at: fetchedAt)
            throw EsportsFeedError.networkUnavailable
        }
    }

    static func slug(for game: EsportsGame) -> String? {
        game.providerSlug
    }

    private static func accepts(url: URL, slug: String) -> Bool {
        guard url.scheme == "https", ["www.esport-calendar.com", "esport-calendar.com"].contains(url.host?.lowercased()),
              url.port == nil || url.port == 443, url.user == nil, url.password == nil, url.fragment == nil,
              url.path == "/calendar.ics" else { return false }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return query == [URLQueryItem(name: "games", value: slug)]
    }
}
