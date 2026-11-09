import Foundation

struct FootballCompetitionAvailabilityWindow: Codable, Equatable, Sendable {
    let start: Date
    let end: Date

    init(now: Date, lookbackDays: Int, lookaheadDays: Int, calendar: Calendar = .autoupdatingCurrent) {
        let today = calendar.startOfDay(for: now)
        // Finished cards use their end time. Include the preceding date so a late-night
        // kickoff finishing inside the configured lookback is discoverable too.
        start = calendar.date(byAdding: .day, value: -lookbackDays - 1, to: today) ?? today
        end = calendar.date(byAdding: .day, value: lookaheadDays, to: today) ?? today
    }

    func contains(_ other: Self) -> Bool {
        start <= other.start && end >= other.end
    }
}

struct FootballCompetitionAvailability: Codable, Sendable {
    static let refreshInterval: TimeInterval = 15 * 60

    let competitionSlug: String
    let fetchedAt: Date
    let window: FootballCompetitionAvailabilityWindow
    let matches: [FootballFixtureMatch]

    static func confirmed(
        from result: FootballFixtureLoadResult, competitionSlug: String,
        window: FootballCompetitionAvailabilityWindow, now: Date
    ) -> Self? {
        guard result.failures.isEmpty, result.availablePageCount > 0 else { return nil }
        return Self(competitionSlug: competitionSlug, fetchedAt: now, window: window, matches: result.matches)
    }

    func isFresh(for requestedWindow: FootballCompetitionAvailabilityWindow, now: Date) -> Bool {
        let age = now.timeIntervalSince(fetchedAt)
        return age >= 0 && age < Self.refreshInterval && window.contains(requestedWindow)
    }
}

struct FootballCompetitionAvailabilityStore: Sendable {
    static let retentionInterval: TimeInterval = 7 * 24 * 60 * 60
    let fileURL: URL

    static func defaultStore() -> Self {
        Self(fileURL: FootballMatchCacheStore.defaultStore().fileURL.deletingLastPathComponent()
            .appendingPathComponent("football-competition-availability.json"))
    }

    func load(now: Date) -> [String: FootballCompetitionAvailability] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([String: FootballCompetitionAvailability].self, from: data) else {
            return [:]
        }
        return entries.filter { key, entry in
            let age = now.timeIntervalSince(entry.fetchedAt)
            return key == entry.competitionSlug && age >= 0 && age <= Self.retentionInterval
        }
    }

    func save(_ entries: [String: FootballCompetitionAvailability]) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(entries).write(to: fileURL, options: [.atomic])
        } catch {
            return
        }
    }
}
