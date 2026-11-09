import Foundation

actor GoogleHolidayFeedClient {
    enum ClientError: LocalizedError, Equatable, Sendable {
        case unavailableCountry(String)
        case invalidResponse
        case unsuccessfulResponse(statusCode: Int)
        case unreadableCalendar
        case retryDeferred(statusCode: Int?, until: Date)

        var errorDescription: String? {
            switch self {
            case .unavailableCountry:
                return L10n.text("One of the selected Google holiday calendars is unavailable.")
            case .invalidResponse, .unreadableCalendar:
                return L10n.text("Google returned an unreadable holiday calendar.")
            case .unsuccessfulResponse, .retryDeferred:
                return L10n.text("Google holiday calendars are temporarily unavailable.")
            }
        }
    }

    private struct CountryLoad: Sendable {
        let country: GoogleHolidayCountry
        var events: [GoogleHolidaySourceEvent] = []
        var error: String?
        var cancelled = false
    }

    static let cacheTTL: TimeInterval = 12 * 60 * 60
    static let requestTimeout: TimeInterval = 20
    static let maximumConcurrentRequests = 8

    private let session: URLSession
    private let transport: HTTPServiceTransport
    private let cacheStore: GoogleHolidayFeedCacheStore?
    private var hasLoadedCache = false
    private var cache: [String: GoogleHolidayFeedCacheEntry] = [:]
    private var failedCountryIDs: Set<String> = []

    init(session: URLSession? = nil, cacheStore: GoogleHolidayFeedCacheStore? = nil) {
        self.cacheStore = cacheStore ?? (session == nil ? .defaultStore() : nil)
        let resolved: URLSession
        if let session { resolved = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = Self.requestTimeout
            configuration.timeoutIntervalForResource = Self.requestTimeout
            configuration.waitsForConnectivity = false
            resolved = URLSession(configuration: configuration)
        }
        self.session = resolved
        self.transport = HTTPServiceTransport(session: resolved, maximumConcurrentRequests: Self.maximumConcurrentRequests)
    }

    func fetchHolidays(countryIDs: Set<String>, now: Date = Date(), forceRefresh: Bool = false) async throws -> [GoogleHolidaySourceEvent] {
        let result = try await fetchHolidayLoadResult(countryIDs: countryIDs, now: now, forceRefresh: forceRefresh)
        if result.availableCountryIDs.isEmpty, !result.isComplete {
            throw ClientError.invalidResponse
        }
        return result.events
    }

    func fetchHolidayLoadResult(
        countryIDs: Set<String>, now: Date = Date(), forceRefresh: Bool = false
    ) async throws -> GoogleHolidayFeedLoadResult {
        if !hasLoadedCache {
            let stored = cacheStore?.load(now: now)
            cache = stored?.countries ?? [:]
            failedCountryIDs = stored?.failedCountryIDs ?? []
            hasLoadedCache = true
        }
        let requestedIDs = Set(countryIDs.map { $0.uppercased() })
        let normalizedIDs = GoogleHolidayCountry.normalizedCountryIDs(requestedIDs)
        let countries = GoogleHolidayCountry.countries(for: normalizedIDs)
        guard requestedIDs == normalizedIDs, countries.count == normalizedIDs.count else {
            throw ClientError.unavailableCountry(requestedIDs.subtracting(normalizedIDs).sorted().joined(separator: ", "))
        }
        for country in countries {
            await ExternalFeedMetrics.shared.recordCheck(source: source(country.id), at: now)
        }
        let countriesToLoad = countries.filter { country in
            if forceRefresh || failedCountryIDs.contains(country.id) { return true }
            guard let entry = cache[country.id] else { return true }
            return now < entry.fetchedAt || now.timeIntervalSince(entry.fetchedAt) >= Self.cacheTTL
        }
        let loadingIDs = Set(countriesToLoad.map(\.id))
        for country in countries where !loadingIDs.contains(country.id) {
            await ExternalFeedMetrics.shared.recordCacheHit(source: source(country.id), dataDate: cache[country.id]?.fetchedAt, at: now)
        }
        var errors: [String: String] = [:]
        let session = self.session
        let transport = self.transport
        for batchStart in stride(from: 0, to: countriesToLoad.count, by: Self.maximumConcurrentRequests) {
            try Task.checkCancellation()
            let batch = Array(countriesToLoad[batchStart..<min(batchStart + Self.maximumConcurrentRequests, countriesToLoad.count)])
            let results = await withTaskGroup(of: CountryLoad.self) { group in
                for country in batch {
                    group.addTask {
                        do {
                            return CountryLoad(country: country, events: try await Self.load(country: country, session: session, transport: transport, now: now))
                        } catch {
                            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                                return CountryLoad(country: country, cancelled: true)
                            }
                            return CountryLoad(country: country, error: error.localizedDescription)
                        }
                    }
                }
                var values: [CountryLoad] = []
                for await value in group { values.append(value) }
                return values
            }
            if results.contains(where: \.cancelled) { throw CancellationError() }
            try Task.checkCancellation()
            for result in results {
                let id = result.country.id
                if let error = result.error {
                    failedCountryIDs.insert(id)
                    errors[id] = error
                } else {
                    cache[id] = GoogleHolidayFeedCacheEntry(events: result.events, fetchedAt: now)
                    failedCountryIDs.remove(id)
                }
                await DataRefreshHealth.shared.record(source: source(id), title: "\(result.country.displayName) holidays", error: result.error, at: now)
            }
            // A later country failure must not discard successful validated downloads.
            cacheStore?.save(.init(countries: cache, failedCountryIDs: failedCountryIDs))
        }
        return GoogleHolidayFeedLoadResult(
            events: countries.flatMap { cache[$0.id]?.events ?? [] },
            availableCountryIDs: Set(countries.compactMap { cache[$0.id] == nil ? nil : $0.id }),
            errorsByCountryID: errors
        )
    }

    private func source(_ id: String) -> String { "google-holidays.\(id.lowercased())" }

    private nonisolated static func load(
        country: GoogleHolidayCountry,
        session: URLSession, transport: HTTPServiceTransport, now: Date
    ) async throws -> [GoogleHolidaySourceEvent] {
        var request = URLRequest(url: country.feedURL)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("text/calendar, text/plain;q=0.9", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let requestStartedAt = Date()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request, at: now)
        } catch HTTPServiceRetryError.deferred(let statusCode, let until) {
            throw ClientError.retryDeferred(statusCode: statusCode, until: until)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            await ExternalFeedMetrics.shared.recordTransportFailure(
                source: "google-holidays.\(country.id.lowercased())",
                duration: Date().timeIntervalSince(requestStartedAt)
            )
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            await ExternalFeedMetrics.shared.recordTransportFailure(
                source: "google-holidays.\(country.id.lowercased())",
                duration: Date().timeIntervalSince(requestStartedAt)
            )
            throw ClientError.invalidResponse
        }
        await ExternalFeedMetrics.shared.recordNetworkResponse(
            source: "google-holidays.\(country.id.lowercased())",
            statusCode: httpResponse.statusCode,
            responseBytes: data.count,
            duration: Date().timeIntervalSince(requestStartedAt)
        )
        guard (200...299).contains(httpResponse.statusCode) else {
            if [403, 429].contains(httpResponse.statusCode) || httpResponse.value(forHTTPHeaderField: "Retry-After") != nil {
                throw ClientError.retryDeferred(statusCode: httpResponse.statusCode, until: HTTPServiceRetryPolicy.retryDate(
                    statusCode: httpResponse.statusCode, retryAfter: httpResponse.value(forHTTPHeaderField: "Retry-After"), now: now
                ))
            }
            throw ClientError.unsuccessfulResponse(statusCode: httpResponse.statusCode)
        }

        do {
            let events = try GoogleHolidayICSParser.parse(data: data, countryID: country.id)
            await ExternalFeedMetrics.shared.recordValidatedData(source: "google-holidays.\(country.id.lowercased())", at: now)
            return events
        } catch {
            await ExternalFeedMetrics.shared.recordDataFailure(source: "google-holidays.\(country.id.lowercased())", validationFailed: true)
            throw ClientError.unreadableCalendar
        }
    }
}
