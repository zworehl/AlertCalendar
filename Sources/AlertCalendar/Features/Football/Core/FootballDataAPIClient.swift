import Foundation

actor FootballDataAPIClient {
    struct TeamResponse: Codable, Equatable, Sendable {
        let countryName: String?
        let isNational: Bool
        let logoURL: URL?
        let venueLocationText: String?
    }

    struct TeamCacheEntry: Codable, Sendable {
        let response: TeamResponse
        let fetchedAt: Date
    }

    struct ScoreboardPageCacheEntry {
        let matches: [FootballFixtureMatch]
        let fetchedAt: Date
    }

    struct SummaryRootCacheEntry {
        let root: [String: Any]
        let fetchedAt: Date
    }

    enum SummaryRootCacheRequirement {
        case any
        case minimumScorerCount(Int)
        case hasStatistics
    }

    struct SummarySnapshot {
        let statusState: FootballFixtureStatusState
        let statusText: String
        let statusDetailText: String?
        let statusPeriod: Int?
        let statusReliability: FootballFixtureStatusReliability
        let competitionNote: String?
        let seriesSummary: FootballFixtureSeriesSummary?
        let locationText: String?
        let actualStartDate: Date?
        let actualEndDate: Date?
        let homeScore: String
        let awayScore: String
        let homeYellowCards: Int
        let awayYellowCards: Int
        let homeRedCards: Int
        let awayRedCards: Int
    }

    let session: URLSession
    let teamCacheStore: FootballTeamCacheStore?
    var teamCache: [String: TeamResponse] = [:]
    var teamCacheFetchedAt: [String: Date] = [:]
    var scoreboardPageCache: [String: ScoreboardPageCacheEntry] = [:]
    var scoreboardPageTasks: [String: Task<[FootballFixtureMatch], Never>] = [:]
    var goalScorersCache: [String: FootballMatchGoalScorers] = [:]
    var athleteCountryCache: [String: String] = [:]
    var missingAthleteCountryIDs: Set<String> = []
    var statisticsCache: [String: [FootballMatchStatistic]] = [:]
    var summaryRootCache: [String: SummaryRootCacheEntry] = [:]
    var summaryRootTasks: [String: Task<Data?, Error>] = [:]

    init(
        session: URLSession? = nil,
        teamCacheStore: FootballTeamCacheStore? = nil
    ) {
        let resolvedTeamCacheStore = teamCacheStore ?? (session == nil ? FootballTeamCacheStore.defaultStore() : nil)
        self.teamCacheStore = resolvedTeamCacheStore
        if let persistedTeamCache = resolvedTeamCacheStore?.load(
            now: AlertCalendarClock.nowRoundedToSecond(),
            ttl: Self.teamCacheTTL
        ) {
            self.teamCache = persistedTeamCache.mapValues(\.response)
            self.teamCacheFetchedAt = persistedTeamCache.mapValues(\.fetchedAt)
        }

        if let session {
            self.session = session
            return
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.resourceTimeout
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 12
        self.session = URLSession(configuration: configuration)
    }

    func fetchMatches(
        for competitions: [FootballCompetitionPreset],
        enrichTeams shouldEnrichTeams: Bool = true
    ) async throws -> [FootballFixtureMatch] {
        let chunks = await withTaskGroup(of: [FootballFixtureMatch].self) { group in
            for competition in competitions {
                group.addTask {
                    await self.fetchMatchesForCompetition(competition)
                }
            }

            var merged: [FootballFixtureMatch] = []
            for await chunk in group {
                merged.append(contentsOf: chunk)
            }
            return merged
        }

        var seen = Set<String>()
        let deduplicated = chunks
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate {
                    return lhs.startDate < rhs.startDate
                }
                return lhs.id < rhs.id
            }

        guard shouldEnrichTeams else { return deduplicated }
        return await enrichTeams(in: deduplicated)
    }

    func fetchMatchesByCompetition(
        for competitions: [FootballCompetitionPreset],
        enrichTeams shouldEnrichTeams: Bool = true
    ) async throws -> [String: [FootballFixtureMatch]] {
        let matches = try await fetchMatches(
            for: competitions,
            enrichTeams: shouldEnrichTeams
        )
        return Dictionary(grouping: matches, by: \.competitionSlug)
    }

    func scoreboardMatchesPage(
        url: URL,
        slug: String,
        competitionName: String,
        competitionCategory: FootballCompetitionCategory? = nil
    ) async -> [FootballFixtureMatch] {
        let cacheKey = url.absoluteString
        let now = AlertCalendarClock.nowRoundedToSecond()

        if let cached = scoreboardPageCache[cacheKey],
           now.timeIntervalSince(cached.fetchedAt) <= Self.scoreboardPageCacheTTL {
            return cached.matches
        }

        let matches: [FootballFixtureMatch]
        if let task = scoreboardPageTasks[cacheKey] {
            matches = await task.value
        } else {
            let task = Task { [session] in
                await Self.fetchMatchesPage(
                    url: url,
                    slug: slug,
                    competitionName: competitionName,
                    session: session,
                    competitionCategory: competitionCategory
                )
            }
            scoreboardPageTasks[cacheKey] = task
            defer { scoreboardPageTasks[cacheKey] = nil }
            matches = await task.value
        }

        cacheScoreboardMatchesPage(matches, for: cacheKey, fetchedAt: now)
        return matches
    }

    func cacheScoreboardMatchesPage(
        _ matches: [FootballFixtureMatch],
        for cacheKey: String,
        fetchedAt: Date
    ) {
        if scoreboardPageCache[cacheKey] == nil,
           scoreboardPageCache.count >= Self.scoreboardPageCacheLimit,
           let oldestKey = scoreboardPageCache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key {
            scoreboardPageCache.removeValue(forKey: oldestKey)
        }

        scoreboardPageCache[cacheKey] = ScoreboardPageCacheEntry(
            matches: matches,
            fetchedAt: fetchedAt
        )
    }

    func summaryRoot(
        url: URL,
        match: FootballFixtureMatch,
        requirement: SummaryRootCacheRequirement = .any
    ) async throws -> [String: Any]? {
        let cacheKey = Self.summaryRootCacheKey(url: url, match: match)
        let now = AlertCalendarClock.nowRoundedToSecond()

        if let cached = summaryRootCache[cacheKey],
           now.timeIntervalSince(cached.fetchedAt) <= Self.summaryRootCacheTTL,
           Self.summaryRoot(cached.root, satisfies: requirement, match: match) {
            return cached.root
        }

        let data: Data?
        if let task = summaryRootTasks[cacheKey] {
            data = try await task.value
        } else {
            let task = Task { [session] in
                try await Self.fetchSummaryData(url: url, session: session)
            }
            summaryRootTasks[cacheKey] = task
            defer { summaryRootTasks[cacheKey] = nil }
            data = try await task.value
        }

        guard let data else { return nil }
        let root = try Self.jsonDictionary(from: data)
        cacheSummaryRoot(root, for: cacheKey, fetchedAt: now)
        return root
    }

    func cacheSummaryRoot(
        _ root: [String: Any],
        for cacheKey: String,
        fetchedAt: Date
    ) {
        if summaryRootCache[cacheKey] == nil,
           summaryRootCache.count >= Self.summaryRootCacheLimit,
           let oldestKey = summaryRootCache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key {
            summaryRootCache.removeValue(forKey: oldestKey)
        }

        summaryRootCache[cacheKey] = SummaryRootCacheEntry(
            root: root,
            fetchedAt: fetchedAt
        )
    }

    func fetchGoalScorers(for match: FootballFixtureMatch) async throws -> FootballMatchGoalScorers? {
        guard match.totalGoals > 0 else { return nil }

        let cacheKey = Self.goalScorersCacheKey(for: match)
        if let cached = goalScorersCache[cacheKey] {
            return cached
        }

        let urls = Self.summaryURLs(for: match)
        var bestScorers: FootballMatchGoalScorers?
        var bestCount = 0
        var lastTransportError: Error?

        for url in urls {
            do {
                guard let root = try await summaryRoot(
                    url: url,
                    match: match,
                    requirement: .minimumScorerCount(match.totalGoals)
                ) else {
                    continue
                }

                guard let candidate = Self.matchGoalScorers(from: root, match: match) else {
                    continue
                }

                let candidateCount = candidate.home.count + candidate.away.count
                if candidateCount > bestCount {
                    bestScorers = candidate
                    bestCount = candidateCount
                }

                if candidateCount >= match.totalGoals {
                    let enrichedCandidate = await enrichedGoalScorers(candidate)
                    goalScorersCache[cacheKey] = enrichedCandidate
                    return enrichedCandidate
                }
            } catch {
                lastTransportError = error
            }
        }

        if let bestScorers {
            return await enrichedGoalScorers(bestScorers)
        }

        if let lastTransportError {
            throw lastTransportError
        }

        return nil
    }

    func fetchMatchStatistics(for match: FootballFixtureMatch) async throws -> [FootballMatchStatistic] {
        guard match.statusState != .scheduled else { return [] }

        let cacheKey = Self.statisticsCacheKey(for: match)
        if let cached = statisticsCache[cacheKey] {
            return cached
        }

        let urls = Self.summaryURLs(for: match)
        var bestStatistics: [FootballMatchStatistic] = []
        var bestCount = 0
        var lastTransportError: Error?

        for url in urls {
            do {
                guard let root = try await summaryRoot(
                    url: url,
                    match: match,
                    requirement: .hasStatistics
                ) else {
                    continue
                }

                let candidate = Self.matchStatistics(from: root)
                if candidate.count > bestCount {
                    bestStatistics = candidate
                    bestCount = candidate.count
                }

                if candidate.count >= 10 {
                    statisticsCache[cacheKey] = candidate
                    return candidate
                }
            } catch {
                lastTransportError = error
            }
        }

        if !bestStatistics.isEmpty {
            statisticsCache[cacheKey] = bestStatistics
            return bestStatistics
        }

        if let lastTransportError {
            throw lastTransportError
        }

        return []
    }

    func refreshStatusesIfNeeded(
        for matches: [FootballFixtureMatch],
        forceSummaryForMatchIDs: Set<String> = []
    ) async -> [FootballFixtureMatch] {
        guard !matches.isEmpty else { return matches }

        let now = AlertCalendarClock.nowRoundedToSecond()
        let candidates = matches.filter { match in
            if forceSummaryForMatchIDs.contains(match.id) {
                return true
            }

            let secondsFromKickoff = now.timeIntervalSince(match.startDate)
            switch match.statusState {
            case .inProgress:
                return true
            case .scheduled, .unknown:
                return secondsFromKickoff >= -Self.summaryPreBufferBeforeKickoff
                    && secondsFromKickoff <= Self.summaryPreBufferAfterKickoff
            case .finished:
                return secondsFromKickoff >= -Self.summaryPreBufferBeforeKickoff
                    && secondsFromKickoff <= Self.summaryPreBufferAfterKickoff
            }
        }

        guard !candidates.isEmpty else { return matches }

        let snapshots = await withTaskGroup(of: (String, SummarySnapshot?).self) { group in
            for match in candidates {
                group.addTask {
                    let snapshot = await self.summarySnapshot(for: match)
                    return (match.id, snapshot)
                }
            }

            var values: [String: SummarySnapshot] = [:]
            for await (matchID, snapshot) in group {
                if let snapshot {
                    values[matchID] = snapshot
                }
            }
            return values
        }

        guard !snapshots.isEmpty else { return matches }

        return matches.map { match in
            guard let snapshot = snapshots[match.id] else { return match }
            let refreshedLocationText = Self.bestAvailableLocationText(
                reportedLocationText: snapshot.locationText,
                fallbackLocationText: match.locationText
            )
            let refreshedActualStartDate = snapshot.actualStartDate ?? match.actualStartDate
            let refreshedActualEndDate = snapshot.actualEndDate ?? match.actualEndDate
            guard snapshot.statusState != match.statusState
                || snapshot.statusText != match.statusText
                || snapshot.statusDetailText != match.statusDetailText
                || snapshot.statusPeriod != match.statusPeriod
                || snapshot.statusReliability != match.statusReliability
                || snapshot.competitionNote != match.competitionNote
                || snapshot.seriesSummary != match.seriesSummary
                || refreshedLocationText != match.locationText
                || refreshedActualStartDate != match.actualStartDate
                || refreshedActualEndDate != match.actualEndDate
                || snapshot.homeScore != match.homeScore
                || snapshot.awayScore != match.awayScore
                || snapshot.homeYellowCards != match.homeYellowCards
                || snapshot.awayYellowCards != match.awayYellowCards
                || snapshot.homeRedCards != match.homeRedCards
                || snapshot.awayRedCards != match.awayRedCards else {
                return match
            }

            return FootballFixtureMatch(
                id: match.id,
                competitionSlug: match.competitionSlug,
                competitionName: match.competitionName,
                competitionStage: match.competitionStage,
                seasonSlug: match.seasonSlug,
                competitionNote: snapshot.competitionNote ?? match.competitionNote,
                seriesSummary: snapshot.seriesSummary ?? match.seriesSummary,
                competitionLogoURL: match.competitionLogoURL,
                locationText: refreshedLocationText,
                startDate: match.startDate,
                actualStartDate: refreshedActualStartDate,
                actualEndDate: refreshedActualEndDate,
                statusState: snapshot.statusState,
                statusText: snapshot.statusText,
                statusDetailText: snapshot.statusDetailText ?? match.statusDetailText,
                statusPeriod: snapshot.statusPeriod ?? match.statusPeriod,
                statusReliability: snapshot.statusReliability,
                homeTeam: match.homeTeam,
                awayTeam: match.awayTeam,
                homeScore: snapshot.homeScore,
                awayScore: snapshot.awayScore,
                homeYellowCards: snapshot.homeYellowCards,
                awayYellowCards: snapshot.awayYellowCards,
                homeRedCards: snapshot.homeRedCards,
                awayRedCards: snapshot.awayRedCards
            )
        }
    }

}
