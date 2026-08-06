import Foundation

actor GoogleHolidayFeedClient {
    enum ClientError: LocalizedError, Equatable, Sendable {
        case unavailableCountry(String)
        case invalidResponse
        case unsuccessfulResponse(statusCode: Int)
        case unreadableCalendar

        var errorDescription: String? {
            switch self {
            case .unavailableCountry:
                return "One of the selected Google holiday calendars is unavailable."
            case .invalidResponse, .unreadableCalendar:
                return "Google returned an unreadable holiday calendar."
            case .unsuccessfulResponse:
                return "Google holiday calendars are temporarily unavailable."
            }
        }
    }

    private struct CacheEntry: Sendable {
        let events: [GoogleHolidaySourceEvent]
        let fetchedAt: Date
    }

    private struct LoadResult: Sendable {
        let countryID: String
        let events: [GoogleHolidaySourceEvent]
    }

    static let cacheTTL: TimeInterval = 12 * 60 * 60
    static let requestTimeout: TimeInterval = 20
    static let maximumConcurrentRequests = 8

    private let session: URLSession
    private var cache: [String: CacheEntry] = [:]

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = Self.requestTimeout
            configuration.timeoutIntervalForResource = Self.requestTimeout
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func fetchHolidays(
        countryIDs: Set<String>,
        now: Date = Date(),
        forceRefresh: Bool = false
    ) async throws -> [GoogleHolidaySourceEvent] {
        let requestedIDs = Set(countryIDs.map { $0.uppercased() })
        let normalizedIDs = GoogleHolidayCountry.normalizedCountryIDs(requestedIDs)
        let countries = GoogleHolidayCountry.countries(for: normalizedIDs)
        guard requestedIDs == normalizedIDs, countries.count == normalizedIDs.count else {
            throw ClientError.unavailableCountry(requestedIDs.subtracting(normalizedIDs).sorted().joined(separator: ", "))
        }

        let countriesToLoad = countries.filter { country in
            guard !forceRefresh, let entry = cache[country.id] else { return true }
            return now.timeIntervalSince(entry.fetchedAt) >= Self.cacheTTL
        }
        for country in countries where !countriesToLoad.contains(country) {
            await ExternalFeedMetrics.shared.recordCacheHit(source: "google-holidays.\(country.id.lowercased())")
        }

        let session = self.session
        var loaded: [LoadResult] = []
        for batchStart in stride(
            from: 0,
            to: countriesToLoad.count,
            by: Self.maximumConcurrentRequests
        ) {
            let batchEnd = min(batchStart + Self.maximumConcurrentRequests, countriesToLoad.count)
            let batch = Array(countriesToLoad[batchStart..<batchEnd])
            let results = try await withThrowingTaskGroup(of: LoadResult.self) { group in
                for country in batch {
                    group.addTask {
                        let events = try await Self.load(country: country, session: session)
                        return LoadResult(countryID: country.id, events: events)
                    }
                }

                var results: [LoadResult] = []
                for try await result in group {
                    results.append(result)
                }
                return results
            }
            loaded.append(contentsOf: results)
        }

        for result in loaded {
            cache[result.countryID] = CacheEntry(events: result.events, fetchedAt: now)
        }

        return countries.flatMap { cache[$0.id]?.events ?? [] }
    }

    private nonisolated static func load(
        country: GoogleHolidayCountry,
        session: URLSession
    ) async throws -> [GoogleHolidaySourceEvent] {
        var request = URLRequest(url: country.feedURL)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("text/calendar, text/plain;q=0.9", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            await ExternalFeedMetrics.shared.recordTransportFailure(
                source: "google-holidays.\(country.id.lowercased())"
            )
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            await ExternalFeedMetrics.shared.recordTransportFailure(
                source: "google-holidays.\(country.id.lowercased())"
            )
            throw ClientError.invalidResponse
        }
        await ExternalFeedMetrics.shared.recordNetworkResponse(
            source: "google-holidays.\(country.id.lowercased())",
            statusCode: httpResponse.statusCode,
            responseBytes: data.count
        )
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ClientError.unsuccessfulResponse(statusCode: httpResponse.statusCode)
        }

        do {
            return try GoogleHolidayICSParser.parse(data: data, countryID: country.id)
        } catch {
            throw ClientError.unreadableCalendar
        }
    }
}
