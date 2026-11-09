import Foundation

/// Disk access occurs on this actor, and only after an explicit load/save.
protocol EsportsCaching: Sendable {
    func load() async -> [EsportsMatch]
    func save(matches: [EsportsMatch]) async throws
}

actor EsportsCacheStore: EsportsCaching {
    private struct Envelope: Codable {
        let version: Int
        let matches: [EsportsMatch]
    }
    private let fileURL: URL
    private let maximumMatches = 5_000

    init(fileURL: URL = EsportsCacheStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    nonisolated static var defaultFileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AlertCalendar/Esports/fixtures-v1.json")
    }

    func load() -> [EsportsMatch] {
        guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 20_000_000,
              let data = try? Data(contentsOf: fileURL),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1 else { return [] }
        return Array(envelope.matches.filter { $0.providerID > 0 && $0.game.providerSlug != nil }.prefix(maximumMatches))
    }

    func save(matches: [EsportsMatch]) throws {
        try Task.checkCancellation()
        let unique = Dictionary(matches.filter { $0.providerID > 0 && $0.game.providerSlug != nil }.map { ($0.id, $0) }, uniquingKeysWith: { a, b in
            a.fetchedAt >= b.fetchedAt ? a : b
        })
        let limited = unique.values.sorted { $0.fetchedAt > $1.fetchedAt }.prefix(maximumMatches)
        let data = try JSONEncoder().encode(Envelope(version: 1, matches: Array(limited)))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}
