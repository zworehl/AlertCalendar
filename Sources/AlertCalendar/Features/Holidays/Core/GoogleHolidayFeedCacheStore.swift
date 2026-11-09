import Foundation

struct GoogleHolidayFeedCacheEntry: Codable, Sendable {
    let events: [GoogleHolidaySourceEvent]
    let fetchedAt: Date
}

struct GoogleHolidayFeedCacheSnapshot: Codable, Sendable {
    var countries: [String: GoogleHolidayFeedCacheEntry] = [:]
    var failedCountryIDs: Set<String> = []
}

struct GoogleHolidayFeedCacheStore: Sendable {
    let fileURL: URL

    static func defaultStore() -> Self {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return Self(fileURL: base.appendingPathComponent("AlertCalendar/google-holiday-feed-cache.json"))
    }

    func load(now: Date) -> GoogleHolidayFeedCacheSnapshot {
        guard let data = try? Data(contentsOf: fileURL),
              var snapshot = try? JSONDecoder().decode(GoogleHolidayFeedCacheSnapshot.self, from: data) else { return .init() }
        snapshot.countries = snapshot.countries.filter {
            let age = now.timeIntervalSince($0.value.fetchedAt)
            return age >= 0 && age <= 180 * 86_400
        }
        return snapshot
    }

    func save(_ snapshot: GoogleHolidayFeedCacheSnapshot) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
        } catch { return }
    }
}

struct GoogleHolidayFeedLoadResult: Sendable {
    let events: [GoogleHolidaySourceEvent]
    let availableCountryIDs: Set<String>
    let errorsByCountryID: [String: String]
    var failedCountryIDs: Set<String> { Set(errorsByCountryID.keys) }
    var isComplete: Bool { errorsByCountryID.isEmpty }
    var warning: String? {
        errorsByCountryID.isEmpty ? nil : errorsByCountryID.keys.sorted().map {
            "\(GoogleHolidayCountry.byID[$0]?.displayName ?? $0): \(errorsByCountryID[$0] ?? "")"
        }.joined(separator: " ")
    }
}
