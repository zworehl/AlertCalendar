import Foundation

actor GameSalesFeedClient {
    static let shared = GameSalesFeedClient()
    static let requestTimeout: TimeInterval = 15
    static let monitorEvaluationInterval: TimeInterval = 15 * 60
    static let refreshInterval: TimeInterval = 6 * 60 * 60
    static let failedRefreshRetryInterval: TimeInterval = 60
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

        func validate(_ text: String) throws {
            let isValid: Bool
            switch self {
            case .steam: isValid = GameSalesFeedDocumentValidator.isSteamSchedule(text)
            case .xbox, .playStation: isValid = GameSalesFeedDocumentValidator.isXML(text, root: "rss")
            case .nintendoSitemap: isValid = GameSalesFeedDocumentValidator.isXML(text, root: "urlset")
            }
            guard isValid else { throw ClientError.invalidResponse }
        }
    }

    private struct SourceLoadResult: Sendable {
        let source: RemoteSource
        let document: LoadedDocument?
        let wasNotModified: Bool
        let error: ClientError?
    }

    private let session: URLSession
    private let cacheStore: GameSalesFeedCacheStore?
    private let health: DataRefreshHealth
    private var sourceCache: [String: GameSalesFeedSourceCacheEntry]
    private var sourceFailures: [String: GameSalesFeedFailureState]
    private var nintendoArticleLastModified: [String: Date]

    init(
        session: URLSession? = nil,
        cacheStore: GameSalesFeedCacheStore? = nil,
        health: DataRefreshHealth = .shared
    ) {
        let resolvedCacheStore = cacheStore ?? (session == nil ? GameSalesFeedCacheStore.defaultStore() : nil)
        let persisted = resolvedCacheStore?.load() ?? .empty
        self.cacheStore = resolvedCacheStore
        self.health = health
        self.sourceCache = persisted.sources
        self.sourceFailures = persisted.failures.mapValues { failure in
            var restored = failure
            // A previous process's offline state must not postpone recovery on launch.
            // Older cache files did not distinguish connectivity from server failures.
            if failure.error == nil || failure.error?.isTransientTransportFailure == true {
                restored.nextRetryAt = .distantPast
            }
            return restored
        }
        self.nintendoArticleLastModified = persisted.nintendoArticleLastModified

        if let session {
            self.session = session
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)
    }

    var hasPendingRefreshFailures: Bool { !sourceFailures.isEmpty }

    var lastSuccessfulRefreshDate: Date? {
        guard sourceFailures.isEmpty, RemoteSource.allCases.allSatisfy({ sourceCache[$0.rawValue] != nil }) else { return nil }
        return RemoteSource.allCases.compactMap { sourceCache[$0.rawValue]?.fetchedAt }.min()
    }

    @discardableResult
    func retryAfterConnectivityRecovery() -> Bool {
        var needsRetry = false
        for key in Array(sourceFailures.keys) {
            guard let failure = sourceFailures[key],
                  failure.error == nil || failure.error?.isTransientTransportFailure == true else { continue }
            sourceFailures[key]?.nextRetryAt = .distantPast
            needsRetry = true
        }
        return needsRetry
    }

    func fetchScheduledSales(
        now: Date = Date(),
        forceRefresh: Bool = false
    ) async throws -> [GameSaleEvent] {
        for source in RemoteSource.allCases {
            await ExternalFeedMetrics.shared.recordCheck(source: source.diagnosticsKey, at: now)
        }
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
            if let failure = sourceFailures[source.rawValue] {
                await restoreHealth(source: source, failure: failure, now: now)
            }
            await ExternalFeedMetrics.shared.recordCacheHit(
                source: source.diagnosticsKey,
                dataDate: sourceCache[source.rawValue]?.fetchedAt,
                at: now
            )
        }

        guard !sourcesToRefresh.isEmpty else {
            if sourceCache.isEmpty, !sourceFailures.isEmpty {
                throw sourceFailures.values.compactMap(\.error).first ?? ClientError.refreshDeferred
            }
            return cachedSales(now: now)
        }

        let session = self.session
        let validators = Dictionary(uniqueKeysWithValues: sourcesToRefresh.map { source in
            let cached = sourceCache[source.rawValue]
            return (source, (cached?.eTag, cached?.lastModified))
        })
        let results = try await withThrowingTaskGroup(of: SourceLoadResult.self) { group in
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
                        if let document {
                            try source.validate(document.text)
                        } else if validators[source]?.0?.isEmpty != false && validators[source]?.1?.isEmpty != false {
                            // A 304 cannot validate a document we have never cached.
                            throw ClientError.invalidResponse
                        }
                        return SourceLoadResult(
                            source: source,
                            document: document,
                            wasNotModified: document == nil,
                            error: nil
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch let error as URLError where error.code == .cancelled {
                        throw CancellationError()
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
                            error: .transportFailure(code: (error as NSError).code)
                        )
                    }
                }
            }

            var loaded: [SourceLoadResult] = []
            for try await result in group {
                loaded.append(result)
            }
            return loaded
        }

        var firstError: ClientError?
        try Task.checkCancellation()
        var receivedSuccessfulResponse = false
        for result in results.sorted(by: { $0.source.rawValue < $1.source.rawValue }) {
            try Task.checkCancellation()
            let key = result.source.rawValue
            if let error = result.error {
                firstError = firstError ?? error
                await recordResult(source: result.source, error: error, now: now)
                continue
            }

            if result.wasNotModified, var cached = sourceCache[key] {
                cached.fetchedAt = now
                sourceCache[key] = cached
                receivedSuccessfulResponse = true
                await recordResult(source: result.source, error: nil, now: now)
                continue
            }
            guard let document = result.document else { continue }

            let sales: [GameSaleEvent]
            var articleError: ClientError?
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
                let nintendo = try await fetchNintendoSales(
                    sitemapXML: document.text,
                    cachedSales: sourceCache[key]?.sales ?? [],
                    now: now,
                    session: session
                )
                sales = nintendo.sales
                articleError = nintendo.error
            }
            try Task.checkCancellation()
            sourceCache[key] = GameSalesFeedSourceCacheEntry(
                sales: sales,
                fetchedAt: now,
                // Retry failed articles even when the sitemap itself is unchanged.
                eTag: articleError == nil ? document.eTag : nil,
                lastModified: articleError == nil ? document.lastModified : nil
            )
            firstError = firstError ?? articleError
            receivedSuccessfulResponse = receivedSuccessfulResponse || articleError == nil
            await recordResult(source: result.source, error: articleError, now: now)
        }

        persistCache()
        if !receivedSuccessfulResponse, sourceCache.isEmpty {
            throw firstError ?? ClientError.invalidResponse
        }
        return cachedSales(now: now)
    }

    private func recordResult(source: RemoteSource, error: ClientError?, now: Date) async {
        let key = source.rawValue
        if let error {
            let previous = sourceFailures[key]
            let failureCount = error.isTransientTransportFailure || previous?.error?.isTransientTransportFailure == true
                ? 1 : (previous?.consecutiveFailureCount ?? 0) + 1
            let failure = GameSalesFeedFailureState(
                consecutiveFailureCount: failureCount,
                nextRetryAt: now.addingTimeInterval(Self.retryDelay(forFailureCount: failureCount, error: error)),
                error: error,
                firstFailedAt: previous?.firstFailedAt ?? now,
                lastFailedAt: now
            )
            sourceFailures[key] = failure
            await restoreHealth(source: source, failure: failure, now: now)
        } else {
            sourceFailures[key] = nil
            await health.record(source: source.diagnosticsKey, title: "\(source.store.title) sales", error: nil, at: now)
        }
    }

    private func restoreHealth(source: RemoteSource, failure: GameSalesFeedFailureState, now: Date) async {
        await health.restore(DataRefreshIssue(
            id: source.diagnosticsKey,
            title: "\(source.store.title) sales",
            detail: (failure.error ?? .refreshDeferred).localizedDescription,
            firstFailedAt: failure.firstFailedAt ?? failure.lastFailedAt ?? now,
            lastFailedAt: failure.lastFailedAt ?? now
        ))
    }

    private func fetchNintendoSales(
        sitemapXML: String,
        cachedSales: [GameSaleEvent],
        now: Date,
        session: URLSession
    ) async throws -> (sales: [GameSaleEvent], error: ClientError?) {
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

        let results = try await withThrowingTaskGroup(of: (NintendoSaleArticleReference, GameSaleEvent?, ClientError?).self) { group in
            for reference in references {
                group.addTask {
                    do {
                        guard let html = try await Self.loadText(
                            from: reference.url,
                            acceptHeader: "text/html,application/xhtml+xml",
                            eTag: nil,
                            lastModified: nil,
                            diagnosticsSource: "game-sales.nintendo-article",
                            session: session
                        ) else { throw ClientError.invalidResponse }
                        guard Self.isReadableNintendoArticle(html.text) else { throw ClientError.invalidResponse }
                        return (reference, Self.parseNintendoSaleArticle(html.text, url: reference.url, now: now), nil)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch let error as URLError where error.code == .cancelled {
                        throw CancellationError()
                    } catch let error as ClientError {
                        return (reference, nil, error)
                    } catch {
                        return (reference, nil, .transportFailure(code: (error as NSError).code))
                    }
                }
            }

            var results: [(NintendoSaleArticleReference, GameSaleEvent?, ClientError?)] = []
            for try await result in group { results.append(result) }
            return results.sorted { $0.0.url.absoluteString < $1.0.url.absoluteString }
        }
        try Task.checkCancellation()
        var sales = cachedSales
        var firstError: ClientError?
        for (reference, sale, error) in results {
            if let error {
                firstError = firstError ?? error
                continue
            }
            nintendoArticleLastModified[reference.url.absoluteString] = reference.lastModified
            sales.removeAll { $0.officialURL == reference.url }
            if let sale { sales.append(sale) }
        }
        return (Self.normalizedSales(sales, now: now), firstError)
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

    nonisolated private static func retryDelay(forFailureCount failureCount: Int, error: ClientError) -> TimeInterval {
        if error.isTransientTransportFailure { return failedRefreshRetryInterval }
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
