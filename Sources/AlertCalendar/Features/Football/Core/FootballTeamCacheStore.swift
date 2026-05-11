import Foundation

struct FootballTeamCacheStore: Sendable {
    let fileURL: URL

    static func defaultStore() -> FootballTeamCacheStore {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let fileURL = applicationSupportURL
            .appendingPathComponent("AlertCalendar", isDirectory: true)
            .appendingPathComponent("football-team-cache.json")
        return FootballTeamCacheStore(fileURL: fileURL)
    }

    func load(
        now: Date,
        ttl: TimeInterval
    ) -> [String: FootballDataAPIClient.TeamCacheEntry]? {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode(
                  [String: FootballDataAPIClient.TeamCacheEntry].self,
                  from: data
              ) else {
            return nil
        }

        return entries.filter { _, entry in
            now.timeIntervalSince(entry.fetchedAt) <= ttl
        }
    }

    func save(_ entries: [String: FootballDataAPIClient.TeamCacheEntry]) {
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
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            return
        }
    }
}
