import Foundation

actor GameSalesFeedClient {
    enum ClientError: LocalizedError, Equatable, Sendable {
        case invalidResponse
        case unsuccessfulResponse(statusCode: Int)
        case unreadableHTML

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The game-sale feeds returned an unreadable response."
            case .unsuccessfulResponse:
                return "The official game-sale feeds are temporarily unavailable."
            case .unreadableHTML:
                return "The official game-sale feeds could not be read."
            }
        }
    }

    static let shared = GameSalesFeedClient()
    static let requestTimeout: TimeInterval = 15
    static let monitorEvaluationInterval: TimeInterval = 15 * 60
    static let refreshInterval: TimeInterval = 6 * 60 * 60
    static let failedRefreshRetryInterval: TimeInterval = monitorEvaluationInterval
    static let steamworksUpcomingEventsURL = URL(
        string: "https://partner.steamgames.com/doc/marketing/upcoming_events?l=english"
    )!
    static let xboxWireStoreFeedURL = URL(
        string: "https://news.xbox.com/en-us/xbox-store/feed/"
    )!
    static let playStationStoreFeedURL = URL(
        string: "https://blog.playstation.com/category/ps-store/feed/"
    )!
    static let nintendoNewsSitemapURL = URL(
        string: "https://www.nintendo.com/us/whatsnew/sitemap.xml"
    )!
    static let nintendoArticleRequestLimit = 20

    private enum RemoteSource: String, CaseIterable, Hashable, Sendable {
        case steam
        case xbox
        case playStation
        case nintendoSitemap

        var url: URL {
            switch self {
            case .steam:
                return GameSalesFeedClient.steamworksUpcomingEventsURL
            case .xbox:
                return GameSalesFeedClient.xboxWireStoreFeedURL
            case .playStation:
                return GameSalesFeedClient.playStationStoreFeedURL
            case .nintendoSitemap:
                return GameSalesFeedClient.nintendoNewsSitemapURL
            }
        }

        var acceptHeader: String {
            switch self {
            case .steam:
                return "text/html,application/xhtml+xml"
            case .xbox, .playStation, .nintendoSitemap:
                return "application/rss+xml,application/xml,text/xml"
            }
        }

        var store: GameStore {
            switch self {
            case .steam: .steam
            case .xbox: .xbox
            case .playStation: .playStation
            case .nintendoSitemap: .nintendoSwitch
            }
        }

        var cacheTTL: TimeInterval {
            GameSalesFeedClient.refreshInterval
        }

        var diagnosticsKey: String {
            "game-sales.\(rawValue)"
        }
    }

    private struct SourceLoadResult: Sendable {
        let source: RemoteSource
        let document: LoadedDocument?
        let wasNotModified: Bool
        let error: ClientError?
    }

    private struct LoadedDocument: Sendable {
        let text: String
        let eTag: String?
        let lastModified: String?
    }

    private let session: URLSession
    private let cacheStore: GameSalesFeedCacheStore?
    private var sourceCache: [String: GameSalesFeedSourceCacheEntry]
    private var sourceFailures: [String: GameSalesFeedFailureState]
    private var nintendoArticleLastModified: [String: Date]

    init(
        session: URLSession? = nil,
        cacheStore: GameSalesFeedCacheStore? = nil
    ) {
        let resolvedCacheStore = cacheStore ?? (session == nil ? GameSalesFeedCacheStore.defaultStore() : nil)
        let persisted = resolvedCacheStore?.load() ?? .empty
        self.cacheStore = resolvedCacheStore
        self.sourceCache = persisted.sources
        self.sourceFailures = persisted.failures
        self.nintendoArticleLastModified = persisted.nintendoArticleLastModified

        if let session {
            self.session = session
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.requestTimeout
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    func fetchScheduledSales(
        now: Date = Date(),
        forceRefresh: Bool = false
    ) async throws -> [GameSaleEvent] {
        let sourcesToRefresh = RemoteSource.allCases.filter { source in
            if forceRefresh {
                return true
            }
            if let failure = sourceFailures[source.rawValue] {
                return now >= failure.nextRetryAt
            }
            guard let cached = sourceCache[source.rawValue], now >= cached.fetchedAt else {
                return true
            }
            return now.timeIntervalSince(cached.fetchedAt) > source.cacheTTL
        }

        let cachedSources = Set(RemoteSource.allCases).subtracting(sourcesToRefresh)
        for source in cachedSources {
            await ExternalFeedMetrics.shared.recordCacheHit(source: source.diagnosticsKey)
        }

        guard !sourcesToRefresh.isEmpty else {
            return cachedSales(now: now)
        }

        let session = self.session
        let validators = Dictionary(uniqueKeysWithValues: sourcesToRefresh.map { source in
            let cached = sourceCache[source.rawValue]
            return (source, (cached?.eTag, cached?.lastModified))
        })
        let results = await withTaskGroup(of: SourceLoadResult.self) { group in
            for source in sourcesToRefresh {
                group.addTask {
                    do {
                        let document = try await Self.loadText(
                            from: source.url,
                            acceptHeader: source.acceptHeader,
                            eTag: validators[source]?.0,
                            lastModified: validators[source]?.1,
                            diagnosticsSource: source.diagnosticsKey,
                            session: session
                        )
                        return SourceLoadResult(
                            source: source,
                            document: document,
                            wasNotModified: document == nil,
                            error: nil
                        )
                    } catch let error as ClientError {
                        return SourceLoadResult(
                            source: source,
                            document: nil,
                            wasNotModified: false,
                            error: error
                        )
                    } catch {
                        return SourceLoadResult(
                            source: source,
                            document: nil,
                            wasNotModified: false,
                            error: .invalidResponse
                        )
                    }
                }
            }

            var loaded: [SourceLoadResult] = []
            for await result in group {
                loaded.append(result)
            }
            return loaded
        }

        var firstError: ClientError?
        var receivedSuccessfulResponse = false
        for result in results {
            let key = result.source.rawValue
            if let error = result.error {
                firstError = firstError ?? error
                let failureCount = (sourceFailures[key]?.consecutiveFailureCount ?? 0) + 1
                sourceFailures[key] = GameSalesFeedFailureState(
                    consecutiveFailureCount: failureCount,
                    nextRetryAt: now.addingTimeInterval(Self.retryDelay(forFailureCount: failureCount))
                )
                continue
            }

            receivedSuccessfulResponse = true
            sourceFailures[key] = nil
            if result.wasNotModified, var cached = sourceCache[key] {
                cached.fetchedAt = now
                sourceCache[key] = cached
                continue
            }
            guard let document = result.document else { continue }

            let sales: [GameSaleEvent]
            switch result.source {
            case .steam:
                sales = Self.parseScheduledSales(fromHTML: document.text, now: now)
            case .xbox:
                sales = GameSalesEditorialRSSParser.parseEditorialRSS(
                    xml: document.text,
                    store: .xbox,
                    now: now
                )
            case .playStation:
                sales = GameSalesEditorialRSSParser.parseEditorialRSS(
                    xml: document.text,
                    store: .playStation,
                    now: now
                )
            case .nintendoSitemap:
                sales = await fetchNintendoSales(
                    sitemapXML: document.text,
                    cachedSales: sourceCache[key]?.sales ?? [],
                    now: now,
                    session: session
                )
            }
            sourceCache[key] = GameSalesFeedSourceCacheEntry(
                sales: sales,
                fetchedAt: now,
                eTag: document.eTag,
                lastModified: document.lastModified
            )
        }

        persistCache()
        if !receivedSuccessfulResponse, sourceCache.isEmpty {
            throw firstError ?? ClientError.invalidResponse
        }
        return cachedSales(now: now)
    }

    private func fetchNintendoSales(
        sitemapXML: String,
        cachedSales: [GameSaleEvent],
        now: Date,
        session: URLSession
    ) async -> [GameSaleEvent] {
        let references = Self.parseNintendoSitemap(sitemapXML, now: now)
            .filter { reference in
                let slug = reference.url.lastPathComponent.lowercased()
                return ["sale", "save", "deal", "discount", "promotion", "offer", "eshop"]
                    .contains { slug.contains($0) }
            }
            .filter { reference in
                nintendoArticleLastModified[reference.url.absoluteString] != reference.lastModified
            }
            .prefix(Self.nintendoArticleRequestLimit)

        let refreshedURLs = Set(references.map(\.url))
        var retainedSales = cachedSales.filter {
            $0.endDateExclusive > now && !refreshedURLs.contains($0.officialURL)
        }

        let refreshedSales = await withTaskGroup(of: (NintendoSaleArticleReference, GameSaleEvent?).self) { group in
            for reference in references {
                group.addTask {
                    guard let html = try? await Self.loadText(
                        from: reference.url,
                        acceptHeader: "text/html,application/xhtml+xml",
                        eTag: nil,
                        lastModified: nil,
                        diagnosticsSource: "game-sales.nintendo-article",
                        session: session
                    ) else {
                        return (reference, nil)
                    }
                    return (reference, Self.parseNintendoSaleArticle(
                        html.text,
                        url: reference.url,
                        now: now
                    ))
                }
            }

            var sales: [GameSaleEvent] = []
            for await (reference, sale) in group {
                nintendoArticleLastModified[reference.url.absoluteString] = reference.lastModified
                if let sale {
                    sales.append(sale)
                }
            }
            return sales
        }
        retainedSales.append(contentsOf: refreshedSales)
        return Self.normalizedSales(retainedSales, now: now)
    }

    nonisolated private static func loadText(
        from url: URL,
        acceptHeader: String,
        eTag: String?,
        lastModified: String?,
        diagnosticsSource: String,
        session: URLSession
    ) async throws -> LoadedDocument? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue(acceptHeader, forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        if let eTag, !eTag.isEmpty {
            request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified, !lastModified.isEmpty {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            await ExternalFeedMetrics.shared.recordTransportFailure(source: diagnosticsSource)
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            await ExternalFeedMetrics.shared.recordTransportFailure(source: diagnosticsSource)
            throw ClientError.invalidResponse
        }
        await ExternalFeedMetrics.shared.recordNetworkResponse(
            source: diagnosticsSource,
            statusCode: httpResponse.statusCode,
            responseBytes: data.count
        )
        if httpResponse.statusCode == 304 {
            return nil
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ClientError.unsuccessfulResponse(statusCode: httpResponse.statusCode)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ClientError.unreadableHTML
        }
        return LoadedDocument(
            text: text,
            eTag: httpResponse.value(forHTTPHeaderField: "ETag"),
            lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified")
        )
    }

    private func cachedSales(now: Date) -> [GameSaleEvent] {
        Self.normalizedSales(sourceCache.values.flatMap(\.sales), now: now)
    }

    private func persistCache() {
        cacheStore?.save(GameSalesFeedCacheSnapshot(
            sources: sourceCache,
            failures: sourceFailures,
            nintendoArticleLastModified: nintendoArticleLastModified
        ))
    }

    nonisolated private static func retryDelay(forFailureCount failureCount: Int) -> TimeInterval {
        let exponent = min(max(failureCount - 1, 0), 6)
        return min(6 * 60 * 60, 15 * 60 * pow(2, Double(exponent)))
    }

    nonisolated private static func normalizedSales(
        _ sales: [GameSaleEvent],
        now: Date
    ) -> [GameSaleEvent] {
        var seenIDs: Set<GameSaleEvent.ID> = []
        var seenCampaigns: Set<String> = []
        var result: [GameSaleEvent] = []

        for sale in sales where sale.startDate < sale.endDateExclusive
            && sale.endDateExclusive > now {
            let foldedTitle = sale.title.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-")
            let campaignKey = [
                sale.store.rawValue,
                foldedTitle,
                String(Int(sale.startDate.timeIntervalSince1970)),
                String(Int(sale.endDateExclusive.timeIntervalSince1970)),
            ].joined(separator: "|")

            guard seenIDs.insert(sale.id).inserted,
                  seenCampaigns.insert(campaignKey).inserted else {
                continue
            }
            result.append(sale)
        }

        return result.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate {
                return lhs.startDate < rhs.startDate
            }
            if lhs.title != rhs.title {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }
}
