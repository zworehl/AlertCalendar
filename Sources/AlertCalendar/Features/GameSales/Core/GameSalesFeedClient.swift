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
    static let cacheTTL: TimeInterval = 30 * 60
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

    private enum RemoteSource: CaseIterable, Hashable, Sendable {
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
    }

    private struct SourceLoadResult: Sendable {
        let source: RemoteSource
        let text: String?
        let error: ClientError?
    }

    private struct CacheEntry {
        let sales: [GameSaleEvent]
        let fetchedAt: Date
    }

    private let session: URLSession
    private var cache: CacheEntry?

    init(session: URLSession? = nil) {
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
        if !forceRefresh,
           let cache,
           now >= cache.fetchedAt,
           now.timeIntervalSince(cache.fetchedAt) <= Self.cacheTTL {
            return cache.sales.filter { $0.endDateExclusive > now }
        }

        let session = session
        let results = await withTaskGroup(of: SourceLoadResult.self) { group in
            for source in RemoteSource.allCases {
                group.addTask {
                    do {
                        let text = try await Self.loadText(
                            from: source.url,
                            acceptHeader: source.acceptHeader,
                            session: session
                        )
                        return SourceLoadResult(source: source, text: text, error: nil)
                    } catch let error as ClientError {
                        return SourceLoadResult(source: source, text: nil, error: error)
                    } catch {
                        return SourceLoadResult(
                            source: source,
                            text: nil,
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

        let documents = Dictionary(
            uniqueKeysWithValues: results.compactMap { result in
                result.text.map { (result.source, $0) }
            }
        )
        guard !documents.isEmpty else {
            let errors = Dictionary(
                uniqueKeysWithValues: results.compactMap { result in
                    result.error.map { (result.source, $0) }
                }
            )
            throw RemoteSource.allCases.compactMap { errors[$0] }.first
                ?? ClientError.invalidResponse
        }

        var sales: [GameSaleEvent] = []
        if let steamHTML = documents[.steam] {
            sales += Self.parseScheduledSales(fromHTML: steamHTML, now: now)
        }
        if let xboxRSS = documents[.xbox] {
            sales += GameSalesEditorialRSSParser.parseEditorialRSS(
                xml: xboxRSS,
                store: .xbox,
                now: now
            )
        }
        if let playStationRSS = documents[.playStation] {
            sales += GameSalesEditorialRSSParser.parseEditorialRSS(
                xml: playStationRSS,
                store: .playStation,
                now: now
            )
        }
        if let nintendoSitemap = documents[.nintendoSitemap] {
            sales += await fetchNintendoSales(
                sitemapXML: nintendoSitemap,
                now: now,
                session: session
            )
        }

        let failedStores = Set(results.compactMap { result in
            result.text == nil ? result.source.store : nil
        })
        let consoleStores: Set<GameStore> = [.xbox, .playStation, .nintendoSwitch]
        if let cache {
            sales += cache.sales.filter { sale in
                failedStores.contains(sale.store) || consoleStores.contains(sale.store)
            }
        }

        sales = Self.normalizedSales(sales, now: now)
        cache = CacheEntry(sales: sales, fetchedAt: now)
        return sales
    }

    private func fetchNintendoSales(
        sitemapXML: String,
        now: Date,
        session: URLSession
    ) async -> [GameSaleEvent] {
        let references = Self.parseNintendoSitemap(sitemapXML, now: now)
            .filter { reference in
                let slug = reference.url.lastPathComponent.lowercased()
                return ["sale", "save", "deal", "discount", "promotion", "offer", "eshop"]
                    .contains { slug.contains($0) }
            }
            .prefix(Self.nintendoArticleRequestLimit)

        return await withTaskGroup(of: GameSaleEvent?.self) { group in
            for reference in references {
                group.addTask {
                    guard let html = try? await Self.loadText(
                        from: reference.url,
                        acceptHeader: "text/html,application/xhtml+xml",
                        session: session
                    ) else {
                        return nil
                    }
                    return Self.parseNintendoSaleArticle(
                        html,
                        url: reference.url,
                        now: now
                    )
                }
            }

            var sales: [GameSaleEvent] = []
            for await sale in group {
                if let sale {
                    sales.append(sale)
                }
            }
            return sales
        }
    }

    nonisolated private static func loadText(
        from url: URL,
        acceptHeader: String,
        session: URLSession
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue(acceptHeader, forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ClientError.unsuccessfulResponse(statusCode: httpResponse.statusCode)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ClientError.unreadableHTML
        }
        return text
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
