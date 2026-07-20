import Foundation

struct GameSalesFeedCacheSnapshot: Codable, Sendable {
    var sources: [String: GameSalesFeedSourceCacheEntry]
    var failures: [String: GameSalesFeedFailureState]
    var nintendoArticleLastModified: [String: Date]

    static let empty = GameSalesFeedCacheSnapshot(
        sources: [:],
        failures: [:],
        nintendoArticleLastModified: [:]
    )
}

struct GameSalesFeedSourceCacheEntry: Codable, Sendable {
    var sales: [GameSaleEvent]
    var fetchedAt: Date
    var eTag: String?
    var lastModified: String?
}

struct GameSalesFeedFailureState: Codable, Sendable {
    var consecutiveFailureCount: Int
    var nextRetryAt: Date
}

struct GameSalesFeedCacheStore: Sendable {
    let fileURL: URL

    static func defaultStore() -> GameSalesFeedCacheStore {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return GameSalesFeedCacheStore(
            fileURL: applicationSupportURL
                .appendingPathComponent("AlertCalendar", isDirectory: true)
                .appendingPathComponent("game-sales-feed-cache.json")
        )
    }

    func load() -> GameSalesFeedCacheSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(GameSalesFeedCacheSnapshot.self, from: data)
    }

    func save(_ snapshot: GameSalesFeedCacheSnapshot) {
        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directoryURL.path) {
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(snapshot).write(to: fileURL, options: [.atomic])
        } catch {
            return
        }
    }
}
