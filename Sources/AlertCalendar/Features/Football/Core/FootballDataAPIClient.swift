import Foundation

actor FootballDataAPIClient {
    let session: URLSession
    let teamCacheStore: FootballTeamCacheStore?
    var teamCache: [String: TeamResponse] = [:]
    var teamCacheFetchedAt: [String: Date] = [:]
    var scoreboardPageCache: [String: ScoreboardPageCacheEntry] = [:]
    var scoreboardPageTasks: [String: Task<[FootballFixtureMatch], Error>] = [:]
    var rejectedScoreboardRanges: [String: Date] = [:]
    var scoreboardCalendars: [String: (calendar: FootballScoreboardCalendar?, fetchedAt: Date)] = [:]
    var scoreboardCalendarTasks: [String: Task<FootballScoreboardCalendar?, Never>] = [:]
    var scoreboardPageFailures = AlertCalendarLRUCache<String, ScoreboardPageFailure>(capacity: 320)
    var goalScorersCache = AlertCalendarLRUCache<String, FootballMatchGoalScorers>(capacity: 160)
    var athleteCountryCache = AlertCalendarLRUCache<String, String>(capacity: 320)
    var missingAthleteCountryIDs = AlertCalendarLRUCache<String, Bool>(capacity: 320)
    var statisticsCache = AlertCalendarLRUCache<String, [FootballMatchStatistic]>(capacity: 160)
    var summaryRootCache: [String: SummaryRootCacheEntry] = [:]
    var summaryRootTasks: [String: Task<Data?, Error>] = [:]
    var summaryRootFailures = AlertCalendarLRUCache<String, (count: Int, nextRetryAt: Date)>(capacity: 120)

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
        enrichTeams shouldEnrichTeams: Bool = true,
        forceRefresh: Bool = false
    ) async throws -> [FootballFixtureMatch] {
        let result = try await fetchFixtureLoadResult(
            for: competitions, enrichTeams: shouldEnrichTeams, forceRefresh: forceRefresh
        )
        return try result.requireAvailableMatches()
    }

    func fetchMatchesByCompetition(
        for competitions: [FootballCompetitionPreset],
        enrichTeams shouldEnrichTeams: Bool = true,
        forceRefresh: Bool = false
    ) async throws -> [String: [FootballFixtureMatch]] {
        let matches = try await fetchMatches(
            for: competitions,
            enrichTeams: shouldEnrichTeams,
            forceRefresh: forceRefresh
        )
        return Dictionary(grouping: matches, by: \.competitionSlug)
    }

    func scoreboardMatchesPage(
        url: URL,
        slug: String,
        competitionName: String,
        competitionCategory: FootballCompetitionCategory? = nil,
        forceRefresh: Bool = false
    ) async throws -> [FootballFixtureMatch] {
        let cacheKey = url.absoluteString
        let now = AlertCalendarClock.nowRoundedToSecond()
        let diagnosticsSource = "football.scoreboard.\(slug)"
        await ExternalFeedMetrics.shared.recordCheck(source: diagnosticsSource, at: now)

        if !forceRefresh,
           scoreboardPageFailures.value(forKey: cacheKey) == nil,
           let cached = scoreboardPageCache[cacheKey],
           now.timeIntervalSince(cached.fetchedAt) <= Self.scoreboardPageCacheTTL(for: url, now: now) {
            await ExternalFeedMetrics.shared.recordCacheHit(
                source: diagnosticsSource,
                dataDate: cached.fetchedAt,
                at: now
            )
            return cached.matches
        }

        if let failure = scoreboardPageFailures.value(forKey: cacheKey),
           !forceRefresh || (failure.rateLimitedUntil.map { now < $0 } ?? false),
           now < failure.nextRetryAt {
            if let cached = scoreboardPageCache[cacheKey] {
                await ExternalFeedMetrics.shared.recordCacheHit(
                    source: "\(diagnosticsSource).stale",
                    dataDate: cached.fetchedAt,
                    at: now
                )
                return cached.matches
            }
            throw ClientError.unavailable(failure.reason)
        }

        if let task = scoreboardPageTasks[cacheKey] {
            await ExternalFeedMetrics.shared.recordCoalescedRequest(source: diagnosticsSource)
            return try await task.value
        }
        let task = Task {
            try await self.refreshScoreboardPage(
                url: url, slug: slug, competitionName: competitionName, competitionCategory: competitionCategory
            )
        }
        scoreboardPageTasks[cacheKey] = task
        defer { scoreboardPageTasks[cacheKey] = nil }
        return try await task.value
    }

    private func refreshScoreboardPage(
        url: URL, slug: String, competitionName: String, competitionCategory: FootballCompetitionCategory?
    ) async throws -> [FootballFixtureMatch] {
        let cacheKey = url.absoluteString
        do {
            let matches = try await Self.fetchScoreboardPageWithRetry(
                url: url, slug: slug, competitionName: competitionName, session: session,
                competitionCategory: competitionCategory
            )
            scoreboardPageFailures.removeValue(forKey: cacheKey)
            cacheScoreboardMatchesPage(matches, for: cacheKey, fetchedAt: AlertCalendarClock.nowRoundedToSecond())
            return matches
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            let failureCount = (scoreboardPageFailures.value(forKey: cacheKey)?.count ?? 0) + 1
            let failedAt = AlertCalendarClock.nowRoundedToSecond()
            let limitedUntil: Date?
            if case .rateLimited(let until) = error as? ClientError { limitedUntil = until } else { limitedUntil = nil }
            scoreboardPageFailures.insert(
                ScoreboardPageFailure(
                    count: failureCount,
                    nextRetryAt: max(failedAt.addingTimeInterval(Self.scoreboardRetryDelay(forFailureCount: failureCount)), limitedUntil ?? failedAt),
                    failedAt: failedAt,
                    reason: Self.fixtureFailureDescription(error),
                    rateLimitedUntil: limitedUntil,
                    rejectedRange: Self.isRejectedScoreboardRange(error)
                ),
                forKey: cacheKey
            )
            if let cached = scoreboardPageCache[cacheKey] {
                return cached.matches
            }
            throw error
        }
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

    nonisolated static func scoreboardRetryDelay(forFailureCount failureCount: Int) -> TimeInterval {
        let exponent = min(max(failureCount - 1, 0), 6)
        return min(6 * 60 * 60, 60 * pow(2, Double(exponent)))
    }

    func summaryRoot(
        url: URL,
        match: FootballFixtureMatch,
        requirement: SummaryRootCacheRequirement = .any
    ) async throws -> [String: Any]? {
        let cacheKey = Self.summaryRootCacheKey(url: url, match: match)
        let now = AlertCalendarClock.nowRoundedToSecond()
        await ExternalFeedMetrics.shared.recordCheck(source: "football.summary", at: now)

        if let cached = summaryRootCache[cacheKey],
           now.timeIntervalSince(cached.fetchedAt) <= Self.summaryRootCacheTTL,
           Self.summaryRoot(cached.root, satisfies: requirement, match: match) {
            await ExternalFeedMetrics.shared.recordCacheHit(
                source: "football.summary",
                dataDate: cached.fetchedAt,
                at: now
            )
            return cached.root
        }

        if let failure = summaryRootFailures.value(forKey: cacheKey), now < failure.nextRetryAt {
            if let cached = summaryRootCache[cacheKey],
               Self.summaryRoot(cached.root, satisfies: requirement, match: match) {
                await ExternalFeedMetrics.shared.recordCacheHit(
                    source: "football.summary.stale",
                    dataDate: cached.fetchedAt,
                    at: now
                )
                return cached.root
            }
            throw ClientError.unsuccessfulResponse(statusCode: 429)
        }

        do {
            let data: Data?
            if let task = summaryRootTasks[cacheKey] {
                await ExternalFeedMetrics.shared.recordCoalescedRequest(source: "football.summary")
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
            summaryRootFailures.removeValue(forKey: cacheKey)
            cacheSummaryRoot(root, for: cacheKey, fetchedAt: now)
            return root
        } catch {
            let count = (summaryRootFailures.value(forKey: cacheKey)?.count ?? 0) + 1
            summaryRootFailures.insert(
                (
                    count,
                    now.addingTimeInterval(Self.scoreboardRetryDelay(forFailureCount: count))
                ),
                forKey: cacheKey
            )
            if let cached = summaryRootCache[cacheKey],
               Self.summaryRoot(cached.root, satisfies: requirement, match: match) {
                return cached.root
            }
            throw error
        }
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


    func fetchMatchStatistics(for match: FootballFixtureMatch) async throws -> [FootballMatchStatistic] {
        guard match.statusState != .scheduled else { return [] }

        let cacheKey = Self.statisticsCacheKey(for: match)
        if let cached = statisticsCache.value(forKey: cacheKey) {
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
                    statisticsCache.insert(candidate, forKey: cacheKey)
                    return candidate
                }
            } catch {
                lastTransportError = error
            }
        }

        if !bestStatistics.isEmpty {
            statisticsCache.insert(bestStatistics, forKey: cacheKey)
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
            let refreshedOfficialWinner = snapshot.officialWinner ?? match.officialWinner
            let refreshedHomeShootoutScore = snapshot.homeShootoutScore ?? match.homeShootoutScore
            let refreshedAwayShootoutScore = snapshot.awayShootoutScore ?? match.awayShootoutScore
            let refreshedPregameProbabilities = snapshot.pregameOutcomeProbabilities
                ?? match.pregameOutcomeProbabilities
            let refreshedOutcomeProbabilities: FootballMatchOutcomeProbabilities?
            if let probabilities = snapshot.outcomeProbabilities {
                refreshedOutcomeProbabilities = probabilities
            } else if match.outcomeProbabilities?.source == .liveMarketOdds {
                // A successfully parsed snapshot with no active market invalidates
                // the prior in-play quote. Transport failures never reach this merge.
                refreshedOutcomeProbabilities = nil
            } else {
                refreshedOutcomeProbabilities = match.outcomeProbabilities
            }
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
                || snapshot.awayRedCards != match.awayRedCards
                || refreshedOfficialWinner != match.officialWinner
                || refreshedHomeShootoutScore != match.homeShootoutScore
                || refreshedAwayShootoutScore != match.awayShootoutScore
                || refreshedPregameProbabilities != match.pregameOutcomeProbabilities
                || refreshedOutcomeProbabilities != match.outcomeProbabilities else {
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
                awayRedCards: snapshot.awayRedCards,
                officialWinner: refreshedOfficialWinner,
                homeShootoutScore: refreshedHomeShootoutScore,
                awayShootoutScore: refreshedAwayShootoutScore,
                pregameOutcomeProbabilities: refreshedPregameProbabilities,
                outcomeProbabilities: refreshedOutcomeProbabilities
            )
        }
    }

}
