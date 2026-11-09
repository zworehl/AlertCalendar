import Foundation

extension FootballDataAPIClient {
    func fetchGoalScorers(for match: FootballFixtureMatch, enrichCountries: Bool = true) async throws -> FootballMatchGoalScorers? {
        guard match.totalGoals > 0 else { return nil }

        let cacheKey = Self.goalScorersCacheKey(for: match)
        if let cached = goalScorersCache.value(forKey: cacheKey) {
            return enrichCountries ? await enrichedGoalScorers(cached) : cached
        }

        let urls = Self.summaryURLs(for: match)
        var bestScorers: FootballMatchGoalScorers?
        var bestCount = 0
        var lastTransportError: Error?
        var receivedSummary = false

        for url in urls {
            try Task.checkCancellation()
            do {
                guard let root = try await summaryRoot(
                    url: url,
                    match: match,
                    requirement: .minimumScorerCount(match.totalGoals)
                ) else {
                    continue
                }

                receivedSummary = true
                guard let candidate = Self.matchGoalScorers(from: root, match: match) else {
                    continue
                }

                let candidateCount = candidate.home.count + candidate.away.count
                if candidateCount > bestCount {
                    bestScorers = candidate
                    bestCount = candidateCount
                }

                if candidateCount >= match.totalGoals {
                    goalScorersCache.insert(candidate, forKey: cacheKey)
                    return enrichCountries ? await enrichedGoalScorers(candidate) : candidate
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                lastTransportError = error
            }
        }

        if let bestScorers {
            return enrichCountries ? await enrichedGoalScorers(bestScorers) : bestScorers
        }

        if let lastTransportError, !receivedSummary {
            throw lastTransportError
        }

        return nil
    }

}
