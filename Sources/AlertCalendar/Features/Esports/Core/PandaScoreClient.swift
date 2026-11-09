import Foundation

protocol EsportsProviding: Sendable {
    func load(game: EsportsGame, from: Date, to: Date, token: String, trackedIDs: [Int]) async throws -> EsportsLoadResult
}

/// Free REST fixtures only: running status does not imply continuous live scores.
actor PandaScoreClient: EsportsProviding {
    private let transport: HTTPServiceTransport
    private let maximumPages: Int
    private let hourlyRequestLimit: Int
    private let now: @Sendable () -> Date
    private var requestDates: [Date] = []
    private var providerRetryAt: Date?
    private var trackedCursor = 0
    private let maximumTrackedDetails = 8

    init(session: URLSession = AlertCalendarHTTPClient.shared, transport: HTTPServiceTransport? = nil,
         maximumPages: Int = 4, hourlyRequestLimit: Int = 600, now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport ?? HTTPServiceTransport(session: session, maximumConcurrentRequests: 2, now: now)
        self.maximumPages = min(max(1, maximumPages), 10)
        self.hourlyRequestLimit = min(max(1, hourlyRequestLimit), 800)
        self.now = now
    }

    func load(game: EsportsGame, from: Date, to: Date, token: String, trackedIDs: [Int] = []) async throws -> EsportsLoadResult {
        try Task.checkCancellation()
        guard let prefix = game.providerSlug else { throw PandaScoreError.unsupportedGame }
        guard from < to, to.timeIntervalSince(from) <= 550 * 86_400 else { throw PandaScoreError.invalidWindow }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw PandaScoreError.missingToken }
        guard PandaScoreTokenKeychainStore.isValid(token) else { throw PandaScoreError.invalidToken }
        let fetchedAt = now()
        let source = "esports.\(game.rawValue)"
        await ExternalFeedMetrics.shared.recordCheck(source: source, at: fetchedAt)
        var matches: [Int: EsportsMatch] = [:]
        var issues: [EsportsLoadIssue] = []
        var successfulPages = 0
        var firstError: PandaScoreError?

        for section in ["upcoming", "running", "past"] {
            try Task.checkCancellation()
            var url: URL? = try listURL(prefix: prefix, section: section, from: from, to: to)
            var seen: Set<URL> = []
            var page = 0
            do {
                while let current = url {
                    try Task.checkCancellation()
                    guard seen.insert(current).inserted else { issues.append(.init(kind: .invalidPagination)); break }
                    let (data, response) = try await request(current, token: token, source: source)
                    let decoded = try PandaScoreMatchDTO.decoder().decode(PandaScoreLossyArray<PandaScoreMatchDTO>.self, from: data)
                    successfulPages += 1
                    var rejected = decoded.rejected
                    for dto in decoded.values {
                        if let match = try? dto.match(game: game, fetchedAt: fetchedAt) {
                            let pendingDate = (section == "upcoming" && match.scheduledAt == nil) || match.status == .postponed
                            if trackedIDs.contains(match.providerID) || match.status == .running || pendingDate || match.scheduledAt.map({ $0 >= from && $0 <= to }) == true {
                                matches[match.providerID] = match
                            }
                        } else { rejected += 1 }
                    }
                    if rejected > 0 { issues.append(.init(kind: .invalidPayload)) }
                    else { await ExternalFeedMetrics.shared.recordValidatedData(source: source, at: fetchedAt) }
                    page += 1
                    let next = try nextURL(response: response, expectedPath: current.path)
                    if next != nil, page >= maximumPages { issues.append(.init(kind: .paginationLimit)); break }
                    url = next
                }
            } catch {
                let failure = try sanitized(error)
                if failure == .unauthorized { throw failure }
                firstError = firstError ?? failure
                issues.append(issue(for: failure))
                if shouldStop(failure) { break }
            }
        }

        // Existing matches can disappear from the three lists after cancellation
        // or postponement. Refresh their generic free endpoint explicitly.
        let missing = Array(Set(trackedIDs.filter { $0 > 0 && matches[$0] == nil })).sorted()
        let start = missing.isEmpty ? 0 : trackedCursor % missing.count
        let details = (0..<min(missing.count, maximumTrackedDetails)).map { missing[(start + $0) % missing.count] }
        trackedCursor += details.count
        if missing.count > maximumTrackedDetails { issues.append(.init(kind: .paginationLimit)) }
        if firstError.map(shouldStop) != true {
            for id in details {
                do {
                    let (data, _) = try await request(URL(string: "https://api.pandascore.co/matches/\(id)")!, token: token, source: source)
                    let dto = try PandaScoreMatchDTO.decoder().decode(PandaScoreMatchDTO.self, from: data)
                    let match = try dto.match(game: game, fetchedAt: fetchedAt)
                    guard match.providerID == id else { throw PandaScoreError.invalidPayload }
                    matches[id] = match
                    successfulPages += 1
                } catch {
                    let failure = try sanitized(error)
                    if failure == .unauthorized { throw failure }
                    firstError = firstError ?? failure
                    issues.append(issue(for: failure))
                    if shouldStop(failure) { break }
                }
            }
        }
        if !issues.isEmpty { await ExternalFeedMetrics.shared.recordDataFailure(source: source, validationFailed: issues.contains { $0.kind == .invalidPayload }) }
        if successfulPages == 0 { throw firstError ?? PandaScoreError.invalidPayload }
        return EsportsLoadResult(matches: matches.values.sorted { ($0.scheduledAt ?? .distantFuture, $0.providerID) < ($1.scheduledAt ?? .distantFuture, $1.providerID) },
                                 isComplete: issues.isEmpty, issues: issues, fetchedAt: fetchedAt)
    }

    private func listURL(prefix: String, section: String, from: Date, to: Date) throws -> URL {
        var components = URLComponents(string: "https://api.pandascore.co/\(prefix)/matches/\(section)")!
        let formatter = ISO8601DateFormatter()
        components.queryItems = [URLQueryItem(name: "per_page", value: "100"), URLQueryItem(name: "sort", value: "scheduled_at,id")]
        if section != "running" {
            components.queryItems?.append(URLQueryItem(name: "range[scheduled_at]", value: "\(formatter.string(from: from)),\(formatter.string(from: to))"))
        }
        guard let url = components.url else { throw PandaScoreError.invalidWindow }
        return url
    }

    private func request(_ url: URL, token: String, source: String) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let date = now()
        if let until = providerRetryAt, date < until { throw PandaScoreError.rateLimited(until: until) }
        requestDates.removeAll { date.timeIntervalSince($0) >= 3_600 }
        guard requestDates.count < hourlyRequestLimit else { throw PandaScoreError.requestBudget(until: (requestDates.first ?? date).addingTimeInterval(3_600)) }
        requestDates.append(date)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let start = Date()
        let data: Data
        let response: URLResponse
        do { (data, response) = try await transport.data(for: request) }
        catch {
            if error is HTTPServiceRetryError { throw error }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            await ExternalFeedMetrics.shared.recordTransportFailure(source: source, duration: Date().timeIntervalSince(start), at: date)
            throw PandaScoreError.networkUnavailable
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw PandaScoreError.invalidResponse }
        await ExternalFeedMetrics.shared.recordNetworkResponse(source: source, statusCode: http.statusCode, responseBytes: data.count,
                                                               duration: Date().timeIntervalSince(start), at: date)
        guard let returnedURL = http.url, Self.isProviderURL(returnedURL), returnedURL.path == url.path else { throw PandaScoreError.invalidResponse }
        if http.value(forHTTPHeaderField: "X-Rate-Limit-Remaining").flatMap(Int.init) == 0 {
            providerRetryAt = HTTPServiceRetryPolicy.retryDate(statusCode: 429, retryAfter: http.value(forHTTPHeaderField: "Retry-After"), now: date)
        }
        switch http.statusCode {
        case 200: break
        case 401: throw PandaScoreError.unauthorized
        case 403: throw PandaScoreError.unavailable
        case 429: throw PandaScoreError.rateLimited(until: HTTPServiceRetryPolicy.retryDate(statusCode: 429, retryAfter: http.value(forHTTPHeaderField: "Retry-After"), now: date))
        default: throw PandaScoreError.unexpectedStatus(http.statusCode)
        }
        guard data.count <= 5_000_000 else { throw PandaScoreError.invalidPayload }
        return (data, http)
    }

    private func nextURL(response: HTTPURLResponse, expectedPath: String) throws -> URL? {
        guard let link = response.value(forHTTPHeaderField: "Link") else { return nil }
        let expression = try NSRegularExpression(pattern: "<([^>]+)>\\s*;\\s*rel=\"?([^\";,\\s]+)\"?")
        for match in expression.matches(in: link, range: NSRange(link.startIndex..., in: link)) {
            guard let relationRange = Range(match.range(at: 2), in: link), link[relationRange] == "next" else { continue }
            guard let urlRange = Range(match.range(at: 1), in: link),
                  let url = URL(string: String(link[urlRange])), Self.isProviderURL(url), url.path == expectedPath else {
                throw PandaScorePaginationError.invalid
            }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard items.allSatisfy({ !["token", "access_token"].contains($0.name.lowercased()) }) else { throw PandaScorePaginationError.invalid }
            return url
        }
        return nil
    }

    private static func isProviderURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == "api.pandascore.co" && (url.port == nil || url.port == 443)
            && url.user == nil && url.password == nil && url.fragment == nil
    }

    private func sanitized(_ error: Error) throws -> PandaScoreError {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
        if let error = error as? PandaScoreError { return error }
        if case HTTPServiceRetryError.deferred(let status, let until) = error { return .retryDeferred(statusCode: status, until: until) }
        if error is PandaScorePaginationError { return .invalidResponse }
        if error is DecodingError { return .invalidPayload }
        return .networkUnavailable
    }

    private func shouldStop(_ error: PandaScoreError) -> Bool {
        switch error {
        case .unauthorized, .unavailable, .rateLimited, .retryDeferred, .requestBudget, .networkUnavailable: true
        default: false
        }
    }

    private func issue(for error: PandaScoreError) -> EsportsLoadIssue {
        switch error {
        case .unauthorized: .init(kind: .unauthorized, statusCode: 401)
        case .unavailable: .init(kind: .unavailable, statusCode: 403)
        case .rateLimited(let until): .init(kind: .rateLimited, statusCode: 429, retryAt: until)
        case .requestBudget(let until): .init(kind: .requestBudget, retryAt: until)
        case .retryDeferred(let status, let until): .init(kind: status == 429 ? .rateLimited : .requestFailed, statusCode: status, retryAt: until)
        case .invalidPayload: .init(kind: .invalidPayload)
        case .invalidResponse: .init(kind: .invalidPagination)
        case .unexpectedStatus(let code): .init(kind: .requestFailed, statusCode: code)
        default: .init(kind: .requestFailed)
        }
    }
}

private enum PandaScorePaginationError: Error { case invalid }
