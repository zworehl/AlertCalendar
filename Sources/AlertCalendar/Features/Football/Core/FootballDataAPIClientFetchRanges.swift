import Foundation

struct FootballScoreboardDateRange: Hashable, Sendable {
    let start: Date
    let end: Date
}

extension FootballDataAPIClient {
    func fetchMatchesForCompetitionDateRanges(
        _ competition: FootballCompetitionPreset,
        dateRanges: [(Date, Date)],
        forceRefresh: Bool = false
    ) async throws -> [FootballFixtureMatch] {
        try await withThrowingTaskGroup(of: [FootballFixtureMatch].self) { group in
            for dateRange in dateRanges {
                group.addTask {
                    try await self.fetchMatchesForCompetitionPage(
                        competition,
                        dateRange: dateRange,
                        forceRefresh: forceRefresh
                    )
                }
            }

            var merged: [FootballFixtureMatch] = []
            for try await matches in group {
                merged.append(contentsOf: matches)
            }
            return merged
        }
    }

    func fetchMatches(
        for competitions: [FootballCompetitionPreset],
        dateRangesByCompetitionSlug: [String: [FootballScoreboardDateRange]],
        enrichTeams shouldEnrichTeams: Bool = true,
        forceRefresh: Bool = false
    ) async throws -> [FootballFixtureMatch] {
        let chunks = try await withThrowingTaskGroup(of: [FootballFixtureMatch].self) { group in
            for competition in competitions {
                for range in dateRangesByCompetitionSlug[competition.slug] ?? [] {
                    group.addTask {
                        try await self.fetchMatchesForCompetitionPage(
                            competition,
                            dateRange: (range.start, range.end),
                            forceRefresh: forceRefresh
                        )
                    }
                }
            }

            var merged: [FootballFixtureMatch] = []
            for try await matches in group {
                merged.append(contentsOf: matches)
            }
            return merged
        }

        var seen = Set<String>()
        let deduplicated = chunks
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.startDate == $1.startDate ? $0.id < $1.id : $0.startDate < $1.startDate }
        guard shouldEnrichTeams else { return deduplicated }
        return await enrichTeams(in: deduplicated)
    }

    static func scoreboardDateRanges(
        start: Date,
        end: Date,
        calendar: Calendar
    ) -> [(Date, Date)] {
        let normalizedStart = calendar.startOfDay(for: start)
        let normalizedEnd = calendar.startOfDay(for: end)
        guard normalizedStart <= normalizedEnd else { return [] }

        var ranges: [(Date, Date)] = []
        var chunkStart = normalizedStart
        while chunkStart <= normalizedEnd {
            let chunkEndCandidate = calendar.date(
                byAdding: .day,
                value: scoreboardDateRangeChunkDays - 1,
                to: chunkStart
            ) ?? chunkStart
            let chunkEnd = min(chunkEndCandidate, normalizedEnd)
            ranges.append((chunkStart, chunkEnd))

            guard let nextChunkStart = calendar.date(byAdding: .day, value: 1, to: chunkEnd),
                  nextChunkStart > chunkStart else {
                break
            }
            chunkStart = nextChunkStart
        }

        return ranges
    }
}
