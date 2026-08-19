import Foundation

protocol AgendaSummaryLinkPreviewProviding: Sendable {
    func requestByAddingLinkedPagePreviews(_ request: AgendaSummaryRequest) async -> AgendaSummaryRequest
}

actor AgendaSummaryLinkPreviewClient: AgendaSummaryLinkPreviewProviding {
    typealias HostEligibilityProvider = @Sendable (String) async -> Bool

    private struct Selection: Sendable {
        let url: URL
        var itemKeys: [String]
    }

    private struct CacheEntry: Sendable {
        let preview: String?
        let expiresAt: Date
    }

    private static let maximumLinksPerSummary = 3
    private static let maximumResponseBytes = 64 * 1_024
    private static let maximumRedirects = 2
    private static let requestTimeout: TimeInterval = 5
    private static let successCacheLifetime: TimeInterval = 30 * 60
    private static let failureCacheLifetime: TimeInterval = 5 * 60
    private static let maximumCacheEntries = 48

    private let session: URLSession
    private let hostEligibilityProvider: HostEligibilityProvider
    private var cache: [String: CacheEntry] = [:]

    init(
        session: URLSession? = nil,
        hostEligibilityProvider: @escaping HostEligibilityProvider = {
            await AgendaSummaryPublicHostResolver.resolvesOnlyToPublicAddresses($0)
        }
    ) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = Self.requestTimeout
            configuration.timeoutIntervalForResource = Self.requestTimeout
            configuration.waitsForConnectivity = false
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
        self.hostEligibilityProvider = hostEligibilityProvider
    }

    func requestByAddingLinkedPagePreviews(
        _ request: AgendaSummaryRequest
    ) async -> AgendaSummaryRequest {
        let selections = Self.selections(for: request)
        guard !selections.isEmpty else { return request }

        let now = Date()
        cache = cache.filter { $0.value.expiresAt > now }
        var previewsByURL: [String: String] = [:]
        var uncachedSelections: [Selection] = []
        for selection in selections {
            let key = selection.url.absoluteString
            if let cached = cache[key] {
                previewsByURL[key] = cached.preview
                continue
            }
            uncachedSelections.append(selection)
        }

        let session = self.session
        let hostEligibilityProvider = self.hostEligibilityProvider
        await withTaskGroup(of: (String, String?).self) { group in
            for selection in uncachedSelections {
                group.addTask {
                    let preview = await Self.loadPreview(
                        from: selection.url,
                        session: session,
                        hostEligibilityProvider: hostEligibilityProvider
                    )
                    return (selection.url.absoluteString, preview)
                }
            }

            for await (key, preview) in group {
                let lifetime = preview == nil
                    ? Self.failureCacheLifetime
                    : Self.successCacheLifetime
                cache[key] = CacheEntry(
                    preview: preview,
                    expiresAt: now.addingTimeInterval(lifetime)
                )
                previewsByURL[key] = preview
            }
        }
        trimCacheIfNeeded()

        var previewsByItemKey: [String: String] = [:]
        for selection in selections {
            guard let preview = previewsByURL[selection.url.absoluteString] else { continue }
            for itemKey in selection.itemKeys {
                previewsByItemKey[itemKey] = preview
            }
        }
        return request.addingLinkedPagePreviews(previewsByItemKey)
    }

    private static func selections(for request: AgendaSummaryRequest) -> [Selection] {
        var selections: [Selection] = []
        var indexByURL: [String: Int] = [:]

        for item in request.items {
            for rawURL in item.linkedPageURLs {
                guard let url = AgendaSummaryLinkPreviewURLPolicy.eligibleURL(rawURL) else { continue }
                let key = url.absoluteString
                if let index = indexByURL[key] {
                    selections[index].itemKeys.append(item.sourceKey)
                    break
                }
                guard selections.count < maximumLinksPerSummary else { break }
                indexByURL[key] = selections.count
                selections.append(Selection(url: url, itemKeys: [item.sourceKey]))
                break
            }
        }
        return selections
    }

    private static func loadPreview(
        from initialURL: URL,
        session: URLSession,
        hostEligibilityProvider: HostEligibilityProvider
    ) async -> String? {
        var currentURL = initialURL

        for redirectCount in 0...maximumRedirects {
            guard !Task.isCancelled,
                  let host = currentURL.host?.lowercased(),
                  await hostEligibilityProvider(host) else {
                return nil
            }

            var request = URLRequest(url: currentURL)
            request.timeoutInterval = requestTimeout
            request.httpShouldHandleCookies = false
            request.setValue(
                "text/html,application/xhtml+xml,text/plain;q=0.8",
                forHTTPHeaderField: "Accept"
            )
            request.setValue("bytes=0-\(maximumResponseBytes - 1)", forHTTPHeaderField: "Range")
            request.setValue("AlertCalendar/AgendaSummary", forHTTPHeaderField: "User-Agent")

            do {
                let (bytes, response) = try await session.bytes(
                    for: request,
                    delegate: AgendaSummaryNoRedirectDelegate.shared
                )
                guard let response = response as? HTTPURLResponse else {
                    bytes.task.cancel()
                    return nil
                }

                if (300..<400).contains(response.statusCode),
                   redirectCount < maximumRedirects,
                   let location = response.value(forHTTPHeaderField: "Location"),
                   let redirectURL = URL(string: location, relativeTo: currentURL)?.absoluteURL,
                   let eligibleRedirect = AgendaSummaryLinkPreviewURLPolicy.eligibleURL(redirectURL) {
                    bytes.task.cancel()
                    currentURL = eligibleRedirect
                    continue
                }

                guard (200..<300).contains(response.statusCode),
                      let mimeType = response.mimeType?.lowercased(),
                      mimeType == "text/html"
                        || mimeType == "application/xhtml+xml"
                        || mimeType == "text/plain" else {
                    bytes.task.cancel()
                    return nil
                }

                var data = Data()
                data.reserveCapacity(maximumResponseBytes)
                for try await byte in bytes {
                    data.append(byte)
                    if data.count >= maximumResponseBytes {
                        bytes.task.cancel()
                        break
                    }
                }
                return AgendaSummaryLinkedPageParser.preview(
                    from: data,
                    mimeType: mimeType,
                    textEncodingName: response.textEncodingName
                )
            } catch {
                return nil
            }
        }
        return nil
    }

    private func trimCacheIfNeeded() {
        guard cache.count > Self.maximumCacheEntries else { return }
        let keysToRemove = cache
            .sorted { $0.value.expiresAt < $1.value.expiresAt }
            .prefix(cache.count - Self.maximumCacheEntries)
            .map(\.key)
        for key in keysToRemove {
            cache.removeValue(forKey: key)
        }
    }
}

private final class AgendaSummaryNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = AgendaSummaryNoRedirectDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
