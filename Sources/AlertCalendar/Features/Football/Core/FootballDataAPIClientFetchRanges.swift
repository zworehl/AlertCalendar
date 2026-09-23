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
        let result = try await fetchFixtureLoadResult(
            for: [competition],
            dateRangesByCompetitionSlug: [competition.slug: dateRanges.map {
                FootballScoreboardDateRange(start: $0.0, end: $0.1)
            }],
            enrichTeams: false, forceRefresh: forceRefresh
        )
        return try result.requireAvailableMatches()
    }

    func fetchMatches(
        for competitions: [FootballCompetitionPreset],
        dateRangesByCompetitionSlug: [String: [FootballScoreboardDateRange]],
        enrichTeams shouldEnrichTeams: Bool = true,
        forceRefresh: Bool = false
    ) async throws -> [FootballFixtureMatch] {
        let result = try await fetchFixtureLoadResult(
            for: competitions, dateRangesByCompetitionSlug: dateRangesByCompetitionSlug,
            enrichTeams: shouldEnrichTeams, forceRefresh: forceRefresh, healthScope: "tracked"
        )
        return try result.requireAvailableMatches()
    }

    func fetchFixtureLoadResult(
        for competitions: [FootballCompetitionPreset],
        dateRangesByCompetitionSlug: [String: [FootballScoreboardDateRange]]? = nil,
        enrichTeams shouldEnrichTeams: Bool = true,
        forceRefresh: Bool = false,
        healthScope: String = "browse"
    ) async throws -> FootballFixtureLoadResult {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: AlertCalendarClock.nowRoundedToSecond())
        let rangesBySlug = dateRangesByCompetitionSlug ?? Dictionary(uniqueKeysWithValues: competitions.map { competition in
            let start = calendar.date(byAdding: .day, value: -competition.lookbackDays, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: competition.lookaheadDays, to: today) ?? today
            return (competition.slug, Self.scoreboardDateRanges(start: start, end: end, calendar: calendar).map {
                FootballScoreboardDateRange(start: $0.0, end: $0.1)
            })
        })
        var result = try await withThrowingTaskGroup(of: FootballFixtureLoadResult.self) { group in
            for competition in competitions {
                for range in rangesBySlug[competition.slug] ?? [] {
                    group.addTask {
                        try await self.fixturePageResult(competition, range: range, forceRefresh: forceRefresh)
                    }
                }
            }
            var merged = FootballFixtureLoadResult()
            for try await page in group {
                merged.matches += page.matches
                merged.failures += page.failures
                merged.availablePageCount += page.availablePageCount
            }
            return merged
        }
        try Task.checkCancellation()
        result.failures.sort { ($0.competitionSlug, $0.range.start) < ($1.competitionSlug, $1.range.start) }
        result.matches = result.restoringCachedMatches([])
        result.matches = result.matches.filter { match in
            (rangesBySlug[match.competitionSlug] ?? []).contains { range in
                let end = calendar.date(byAdding: .day, value: 1, to: range.end) ?? range.end
                return match.startDate >= range.start && match.startDate < end
            }
        }
        for competition in competitions where !(rangesBySlug[competition.slug] ?? []).isEmpty {
            let failures = result.failures.filter { $0.competitionSlug == competition.slug }
            await DataRefreshHealth.shared.record(
                source: "football.\(healthScope).\(competition.slug)", title: competition.title,
                error: FootballFixtureLoadResult(failures: failures).warning,
                at: failures.map(\.attemptedAt).max() ?? Date()
            )
        }
        if shouldEnrichTeams { result.matches = await enrichTeams(in: result.matches) }
        return result
    }

    func fixturePageResult(
        _ competition: FootballCompetitionPreset, range: FootballScoreboardDateRange, forceRefresh: Bool
    ) async throws -> FootballFixtureLoadResult {
        let isMultipleDays = !Calendar.current.isDate(range.start, inSameDayAs: range.end)
        if isMultipleDays, let rejectedAt = rejectedScoreboardRanges[competition.slug],
           Date().timeIntervalSince(rejectedAt) < 24 * 60 * 60 {
            return try await dailyFixtureResult(competition, range: range, forceRefresh: forceRefresh)
        }
        var result = FootballFixtureLoadResult()
        var failure: String?
        let url = Self.scoreboardURL(slug: competition.slug, dateRange: (range.start, range.end))
        do {
            result.matches = try await fetchMatchesForCompetitionPage(
                competition, dateRange: (range.start, range.end), forceRefresh: forceRefresh
            )
            result.availablePageCount = 1
            if let url {
                if isMultipleDays, scoreboardPageFailures.value(forKey: url.absoluteString)?.rejectedRange == true {
                    rejectedScoreboardRanges[competition.slug] = Date()
                    scoreboardPageFailures.removeValue(forKey: url.absoluteString)
                    return try await dailyFixtureResult(competition, range: range, forceRefresh: forceRefresh)
                }
                failure = scoreboardPageFailures.value(forKey: url.absoluteString)?.reason
            }
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            if isMultipleDays, Self.isRejectedScoreboardRange(error) {
                rejectedScoreboardRanges[competition.slug] = Date()
                if let url { scoreboardPageFailures.removeValue(forKey: url.absoluteString) }
                return try await dailyFixtureResult(competition, range: range, forceRefresh: forceRefresh)
            }
            failure = Self.fixtureFailureDescription(error)
        }
        if let failure {
            let failedAt = url.flatMap { scoreboardPageFailures.value(forKey: $0.absoluteString)?.failedAt } ?? Date()
            result.failures = [FootballFixtureLoadFailure(competitionSlug: competition.slug, range: range, reason: failure, attemptedAt: failedAt)]
        }
        return result
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
