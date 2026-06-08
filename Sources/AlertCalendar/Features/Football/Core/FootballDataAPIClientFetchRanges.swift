import Foundation

extension FootballDataAPIClient {
    func fetchMatchesForCompetitionDateRanges(
        _ competition: FootballCompetitionPreset,
        dateRanges: [(Date, Date)]
    ) async -> [FootballFixtureMatch] {
        await withTaskGroup(of: [FootballFixtureMatch].self) { group in
            for dateRange in dateRanges {
                group.addTask {
                    await self.fetchMatchesForCompetitionPage(
                        competition,
                        dateRange: dateRange
                    )
                }
            }

            var merged: [FootballFixtureMatch] = []
            for await matches in group {
                merged.append(contentsOf: matches)
            }
            return merged
        }
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
