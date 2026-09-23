import Foundation

struct FootballFixtureLoadFailure: Sendable {
    let competitionSlug: String
    let range: FootballScoreboardDateRange
    let reason: String
    var attemptedAt: Date = Date()
}

struct FootballFixtureLoadResult: Sendable {
    var matches: [FootballFixtureMatch] = []
    var failures: [FootballFixtureLoadFailure] = []
    var availablePageCount = 0

    var warning: String? {
        guard !failures.isEmpty else { return nil }
        let reasons = Set(failures.map(\.reason)).sorted().joined(separator: " ")
        return "\(failures.count) fixture date range(s) could not be refreshed. \(reasons) Available matches are kept; missing ranges will be retried."
    }

    func restoringCachedMatches(_ cached: [FootballFixtureMatch], calendar: Calendar = .current) -> [FootballFixtureMatch] {
        func belongsToFailedRange(_ match: FootballFixtureMatch) -> Bool {
            failures.contains { failure in
                let end = calendar.date(byAdding: .day, value: 1, to: failure.range.end) ?? failure.range.end
                return match.competitionSlug == failure.competitionSlug
                    && match.startDate >= failure.range.start && match.startDate < end
            }
        }
        let retained = cached.filter(belongsToFailedRange)
        let fresh = matches.filter { !belongsToFailedRange($0) }
        var seen = Set<String>()
        return (fresh + retained + matches).filter { seen.insert($0.id).inserted }
            .sorted { $0.startDate == $1.startDate ? $0.id < $1.id : $0.startDate < $1.startDate }
    }

    func requireAvailableMatches() throws -> [FootballFixtureMatch] {
        if availablePageCount == 0, let warning {
            throw FootballDataAPIClient.ClientError.unavailable(warning)
        }
        return matches
    }
}
