import Foundation

extension GameSalesFeedClient {
    enum ClientError: LocalizedError, Equatable, Codable, Sendable {
        case invalidResponse
        case unsuccessfulResponse(statusCode: Int)
        case unreadableHTML
        case transportFailure(code: Int)
        case refreshDeferred

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The game-sale feeds returned an unreadable response."
            case .unsuccessfulResponse:
                return "The official game-sale feeds are temporarily unavailable."
            case .unreadableHTML:
                return "The official game-sale feeds could not be read."
            case .refreshDeferred:
                return "The game-sale feeds have not recovered yet. The app will retry automatically."
            case .transportFailure(let code):
                switch code {
                case URLError.notConnectedToInternet.rawValue:
                    return "The last game-sale update failed while the internet connection was offline. The app will retry automatically."
                case URLError.timedOut.rawValue:
                    return "The game-sale feeds did not respond in time. The app will retry automatically."
                default:
                    return "The game-sale feeds could not be reached. The app will retry automatically."
                }
            }
        }

        var isTransientTransportFailure: Bool {
            guard case .transportFailure(let code) = self else { return false }
            return [URLError.notConnectedToInternet, .networkConnectionLost, .timedOut,
                    .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed]
                .contains { $0.rawValue == code }
        }
    }

    struct LoadedDocument: Sendable {
        let text: String
        let eTag: String?
        let lastModified: String?
    }

    nonisolated static func loadText(
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
        let requestStartedAt = Date()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            await ExternalFeedMetrics.shared.recordTransportFailure(
                source: diagnosticsSource,
                duration: Date().timeIntervalSince(requestStartedAt)
            )
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            await ExternalFeedMetrics.shared.recordTransportFailure(
                source: diagnosticsSource,
                duration: Date().timeIntervalSince(requestStartedAt)
            )
            throw ClientError.invalidResponse
        }
        await ExternalFeedMetrics.shared.recordNetworkResponse(
            source: diagnosticsSource,
            statusCode: httpResponse.statusCode,
            responseBytes: data.count,
            duration: Date().timeIntervalSince(requestStartedAt)
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

}
