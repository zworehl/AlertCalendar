import Foundation

struct FootballMatchCacheSnapshot: Codable, Sendable {
    static let currentVersion = 1

    let version: Int
    let fetchedAt: Date
    let matches: [FootballFixtureMatch]

    init(fetchedAt: Date, matches: [FootballFixtureMatch]) {
        self.version = Self.currentVersion
        self.fetchedAt = fetchedAt
        self.matches = matches
    }
}

struct FootballMatchCacheStore: Sendable {
    static let retentionInterval: TimeInterval = 7 * 24 * 60 * 60

    let fileURL: URL

    static func defaultStore() -> FootballMatchCacheStore {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return FootballMatchCacheStore(
            fileURL: applicationSupportURL
                .appendingPathComponent("AlertCalendar", isDirectory: true)
                .appendingPathComponent("football-match-cache.json")
        )
    }

    func load(
        now: Date,
        retentionInterval: TimeInterval = Self.retentionInterval
    ) -> FootballMatchCacheSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(FootballMatchCacheSnapshot.self, from: data),
              snapshot.version == FootballMatchCacheSnapshot.currentVersion,
              now.timeIntervalSince(snapshot.fetchedAt) >= 0,
              now.timeIntervalSince(snapshot.fetchedAt) <= retentionInterval else {
            return nil
        }
        return snapshot
    }

    func save(_ snapshot: FootballMatchCacheSnapshot) {
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
