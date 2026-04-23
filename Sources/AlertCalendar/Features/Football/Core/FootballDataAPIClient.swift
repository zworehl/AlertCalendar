import Foundation

actor FootballDataAPIClient {
    struct TeamResponse {
        let countryName: String?
        let isNational: Bool
        let logoURL: URL?
        let venueLocationText: String?
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
        let homeScore: String
        let awayScore: String
        let homeYellowCards: Int
        let awayYellowCards: Int
        let homeRedCards: Int
        let awayRedCards: Int
    }

    let session: URLSession
    var teamCache: [String: TeamResponse] = [:]
    var goalScorersCache: [String: FootballMatchGoalScorers] = [:]
    var statisticsCache: [String: [FootballMatchStatistic]] = [:]
    static let requestTimeout: TimeInterval = 8
    static let resourceTimeout: TimeInterval = 20
    static let summaryPreBufferBeforeKickoff: TimeInterval = 15 * 60
    static let summaryPreBufferAfterKickoff: TimeInterval = 3 * 60 * 60
    static let delayedLiveDataWarningAfterKickoff: TimeInterval = 15 * 60
    static let clubCountryByLeaguePrefix: [String: String] = [
        "arg": "Argentina",
        "aut": "Austria",
        "bel": "Belgium",
        "bra": "Brazil",
        "col": "Colombia",
        "cze": "Czech Republic",
        "den": "Denmark",
        "eng": "England",
        "esp": "Spain",
        "fra": "France",
        "ger": "Germany",
        "gre": "Greece",
        "irl": "Republic of Ireland",
        "ita": "Italy",
        "jpn": "Japan",
        "mex": "Mexico",
        "ned": "Netherlands",
        "nir": "Northern Ireland",
        "nor": "Norway",
        "pol": "Poland",
        "por": "Portugal",
        "rou": "Romania",
        "sco": "Scotland",
        "srb": "Serbia",
        "sui": "Switzerland",
        "swe": "Sweden",
        "tur": "Turkey",
        "ukr": "Ukraine",
        "usa": "United States",
        "wal": "Wales",
    ]
    static let britishFootballCountries: Set<String> = [
        "england",
        "scotland",
        "wales",
        "northern ireland",
        "united kingdom",
        "great britain",
    ]
    static let countryIdentityAliases: [String: String] = [
        "usa": "united states",
        "us": "united states",
        "u s a": "united states",
        "turkiye": "turkey",
        "great britain": "united kingdom",
    ]
    static let recognizedCountryLookupKeys: Set<String> = {
        let locale = Locale(identifier: "en_US_POSIX")
        var values = Set<String>()
        for regionCode in Locale.Region.isoRegions.map(\.identifier) {
            guard let name = locale.localizedString(forRegionCode: regionCode) else { continue }
            values.insert(normalizedLookupKey(name))
        }
        return values
    }()
    static let genericClubIdentityTokens: Set<String> = [
        "ac",
        "afc",
        "as",
        "athletic",
        "atletico",
        "cf",
        "city",
        "club",
        "de",
        "del",
        "fc",
        "if",
        "inter",
        "real",
        "sc",
        "sporting",
        "sv",
        "the",
        "united",
    ]

    init(session: URLSession? = nil) {
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
        for competitions: [FootballCompetitionPreset]
    ) async throws -> [FootballFixtureMatch] {
        let chunks = await withTaskGroup(of: [FootballFixtureMatch].self) { group in
            for competition in competitions {
                group.addTask { [session] in
                    await Self.fetchMatchesForCompetition(competition, session: session)
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

        return await enrichTeams(in: deduplicated)
    }

    func fetchMatchesByCompetition(
        for competitions: [FootballCompetitionPreset]
    ) async throws -> [String: [FootballFixtureMatch]] {
        let matches = try await fetchMatches(for: competitions)
        return Dictionary(grouping: matches, by: \.competitionSlug)
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
                guard let root = try await Self.fetchSummaryRoot(url: url, session: session) else {
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
                    goalScorersCache[cacheKey] = candidate
                    return candidate
                }
            } catch {
                lastTransportError = error
            }
        }

        if let bestScorers {
            return bestScorers
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
                guard let root = try await Self.fetchSummaryRoot(url: url, session: session) else {
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
                group.addTask { [session] in
                    let snapshot = await Self.fetchSummarySnapshot(
                        competitionSlug: match.competitionSlug,
                        eventID: match.id,
                        fallbackStartDate: match.startDate,
                        session: session
                    )
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
            guard snapshot.statusState != match.statusState
                || snapshot.statusText != match.statusText
                || snapshot.statusDetailText != match.statusDetailText
                || snapshot.statusPeriod != match.statusPeriod
                || snapshot.statusReliability != match.statusReliability
                || snapshot.competitionNote != match.competitionNote
                || snapshot.seriesSummary != match.seriesSummary
                || refreshedLocationText != match.locationText
                || refreshedActualStartDate != match.actualStartDate
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
