import Foundation

actor FootballDataAPIClient {
    private struct TeamResponse {
        let countryName: String?
        let isNational: Bool
        let logoURL: URL?
        let venueLocationText: String?
    }

    private struct SummarySnapshot {
        let statusState: FootballFixtureStatusState
        let statusText: String
        let statusDetailText: String?
        let statusPeriod: Int?
        let statusReliability: FootballFixtureStatusReliability
        let competitionNote: String?
        let locationText: String?
        let actualStartDate: Date?
        let homeScore: String
        let awayScore: String
        let homeYellowCards: Int
        let awayYellowCards: Int
        let homeRedCards: Int
        let awayRedCards: Int
    }

    private let session: URLSession
    private var teamCache: [String: TeamResponse] = [:]
    private var goalScorersCache: [String: FootballMatchGoalScorers] = [:]
    private var statisticsCache: [String: [FootballMatchStatistic]] = [:]
    private static let requestTimeout: TimeInterval = 8
    private static let resourceTimeout: TimeInterval = 20
    private static let summaryPreBufferBeforeKickoff: TimeInterval = 15 * 60
    private static let summaryPreBufferAfterKickoff: TimeInterval = 3 * 60 * 60
    private static let delayedLiveDataWarningAfterKickoff: TimeInterval = 15 * 60
    private static let clubCountryByLeaguePrefix: [String: String] = [
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
    private static let britishFootballCountries: Set<String> = [
        "england",
        "scotland",
        "wales",
        "northern ireland",
        "united kingdom",
        "great britain",
    ]
    private static let countryIdentityAliases: [String: String] = [
        "usa": "united states",
        "us": "united states",
        "u s a": "united states",
        "turkiye": "turkey",
        "great britain": "united kingdom",
    ]
    private static let recognizedCountryLookupKeys: Set<String> = {
        let locale = Locale(identifier: "en_US_POSIX")
        var values = Set<String>()
        for regionCode in Locale.Region.isoRegions.map(\.identifier) {
            guard let name = locale.localizedString(forRegionCode: regionCode) else { continue }
            values.insert(normalizedLookupKey(name))
        }
        return values
    }()
    private static let genericClubIdentityTokens: Set<String> = [
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
            goalScorersCache[cacheKey] = bestScorers
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

    func refreshStatusesIfNeeded(for matches: [FootballFixtureMatch]) async -> [FootballFixtureMatch] {
        guard !matches.isEmpty else { return matches }

        let now = Date()
        let candidates = matches.filter { match in
            let secondsFromKickoff = now.timeIntervalSince(match.startDate)
            switch match.statusState {
            case .inProgress:
                return true
            case .scheduled, .unknown:
                return secondsFromKickoff >= -Self.summaryPreBufferBeforeKickoff
                    && secondsFromKickoff <= Self.summaryPreBufferAfterKickoff
            case .finished:
                return false
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

    private func enrichTeams(in matches: [FootballFixtureMatch]) async -> [FootballFixtureMatch] {
        let teamIDs = Set(matches.flatMap { [$0.homeTeam.id, $0.awayTeam.id] }.filter { !$0.isEmpty })
        guard !teamIDs.isEmpty else { return matches }

        let fetched = await withTaskGroup(of: (String, TeamResponse?).self) { group in
            for teamID in teamIDs {
                if let cached = teamCache[teamID] {
                    group.addTask {
                        (teamID, cached)
                    }
                    continue
                }

                group.addTask { [session] in
                    let result = await Self.fetchTeamDetails(teamID: teamID, session: session)
                    return (teamID, result)
                }
            }

            var values: [String: TeamResponse] = [:]
            for await (teamID, response) in group {
                if let response {
                    values[teamID] = response
                }
            }
            return values
        }

        if !fetched.isEmpty {
            for (teamID, response) in fetched {
                teamCache[teamID] = response
            }
        }

        return matches.map { match in
            let resolvedHome = teamCache[match.homeTeam.id]
            let resolvedAway = teamCache[match.awayTeam.id]
            let resolvedLocationText = Self.bestAvailableLocationText(
                reportedLocationText: match.locationText,
                fallbackLocationText: resolvedHome?.venueLocationText
            )

            return FootballFixtureMatch(
                id: match.id,
                competitionSlug: match.competitionSlug,
                competitionName: match.competitionName,
                competitionStage: match.competitionStage,
                seasonSlug: match.seasonSlug,
                competitionNote: match.competitionNote,
                competitionLogoURL: match.competitionLogoURL,
                locationText: resolvedLocationText,
                startDate: match.startDate,
                actualStartDate: match.actualStartDate,
                statusState: match.statusState,
                statusText: match.statusText,
                statusDetailText: match.statusDetailText,
                statusPeriod: match.statusPeriod,
                statusReliability: match.statusReliability,
                homeTeam: match.homeTeam.withResolvedDetails(
                    countryName: resolvedHome?.countryName,
                    isNational: resolvedHome?.isNational ?? false,
                    logoURL: resolvedHome?.logoURL
                ),
                awayTeam: match.awayTeam.withResolvedDetails(
                    countryName: resolvedAway?.countryName,
                    isNational: resolvedAway?.isNational ?? false,
                    logoURL: resolvedAway?.logoURL
                ),
                homeScore: match.homeScore,
                awayScore: match.awayScore,
                homeYellowCards: match.homeYellowCards,
                awayYellowCards: match.awayYellowCards,
                homeRedCards: match.homeRedCards,
                awayRedCards: match.awayRedCards
            )
        }
    }

    private static func fetchMatchesForCompetition(
        _ competition: FootballCompetitionPreset,
        session: URLSession
    ) async -> [FootballFixtureMatch] {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let dayStart = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -competition.lookbackDays, to: dayStart) ?? dayStart
        let end = calendar.date(byAdding: .day, value: competition.lookaheadDays, to: dayStart) ?? dayStart
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: end) ?? end.addingTimeInterval(24 * 60 * 60)

        async let primary = fetchMatchesPage(
            slug: competition.slug,
            competitionName: competition.title,
            session: session,
            dateRange: nil
        )
        async let ranged = fetchMatchesPage(
            slug: competition.slug,
            competitionName: competition.title,
            session: session,
            dateRange: (start, end)
        )

        let merged = await primary + ranged
        var seen = Set<String>()
        return merged
            .filter { seen.insert($0.id).inserted }
            .filter { match in
                match.startDate >= start && match.startDate < endExclusive
            }
    }

    private static func goalScorersCacheKey(for match: FootballFixtureMatch) -> String {
        let statusDetail = match.statusDetailText ?? ""
        let statusPeriod = match.statusPeriod.map(String.init) ?? "n/a"
        return "\(match.id)|\(match.homeScore)|\(match.awayScore)|\(match.statusText)|\(statusDetail)|\(statusPeriod)"
    }

    private static func statisticsCacheKey(for match: FootballFixtureMatch) -> String {
        let statusPeriod = match.statusPeriod.map(String.init) ?? "n/a"
        return "\(match.id)|\(match.homeScore)|\(match.awayScore)|\(match.statusText)|\(statusPeriod)"
    }

    private static func summaryURLs(for match: FootballFixtureMatch) -> [URL] {
        var urls: [URL] = []

        let leagueSlug = match.competitionSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        if !leagueSlug.isEmpty,
           var components = URLComponents(
               url: URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/\(leagueSlug)/summary")!,
               resolvingAgainstBaseURL: false
           ) {
            components.queryItems = [URLQueryItem(name: "event", value: match.id)]
            if let url = components.url {
                urls.append(url)
            }
        }

        if var allComponents = URLComponents(
            url: URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/all/summary")!,
            resolvingAgainstBaseURL: false
        ) {
            allComponents.queryItems = [URLQueryItem(name: "event", value: match.id)]
            if let allURL = allComponents.url, !urls.contains(allURL) {
                urls.append(allURL)
            }
        }

        return urls
    }

    private static func fetchSummaryRoot(
        url: URL,
        session: URLSession
    ) async throws -> [String: Any]? {
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.requestTimeout
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        return try jsonDictionary(from: data)
    }

    private static func fetchMatchesPage(
        slug: String,
        competitionName: String,
        session: URLSession,
        dateRange: (Date, Date)?
    ) async -> [FootballFixtureMatch] {
        do {
            var components = URLComponents(
                url: URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/\(slug)/scoreboard")!,
                resolvingAgainstBaseURL: false
            )

            if let dateRange {
                let formatter = DateFormatter()
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = .autoupdatingCurrent
                formatter.dateFormat = "yyyyMMdd"
                components?.queryItems = [
                    URLQueryItem(
                        name: "dates",
                        value: "\(formatter.string(from: dateRange.0))-\(formatter.string(from: dateRange.1))"
                    ),
                ]
            }

            guard let url = components?.url else { return [] }
            var request = URLRequest(url: url)
            request.timeoutInterval = Self.requestTimeout
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }

            let root = try jsonDictionary(from: data)
            let league = (root["leagues"] as? [[String: Any]])?.first
            let resolvedCompetitionName = competitionDisplayName(from: league) ?? competitionName
            let competitionLogoURL = leagueLogoURL(from: league)
            let competitionStage = leagueStageName(from: league)
            let events = root["events"] as? [[String: Any]] ?? []
            return events.compactMap {
                liveMatch(
                    from: $0,
                    competitionSlug: slug,
                    competitionName: resolvedCompetitionName,
                    competitionStage: competitionStage,
                    competitionLogoURL: competitionLogoURL
                )
            }
        } catch {
            return []
        }
    }

    private static func fetchTeamDetails(teamID: String, session: URLSession) async -> TeamResponse? {
        guard !teamID.isEmpty,
              let url = URL(string: "https://sports.core.api.espn.com/v2/sports/soccer/teams/\(teamID)?lang=en&region=us") else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = Self.requestTimeout
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }

            let root = try jsonDictionary(from: data)
            let isNational = (root["isNational"] as? Bool) == true
            let countryName = resolvedTeamCountryName(from: root)
            let venueLocationText = resolvedTeamVenueLocationText(from: root)

            let logos = root["logos"] as? [[String: Any]] ?? []
            let preferredLogo = logos.first(where: { (($0["rel"] as? [String]) ?? []).contains("default") }) ?? logos.first

            return TeamResponse(
                countryName: countryName,
                isNational: isNational,
                logoURL: safeURL(from: stringValue(preferredLogo?["href"])),
                venueLocationText: venueLocationText
            )
        } catch {
            return nil
        }
    }

    static func resolvedTeamCountryName(from root: [String: Any]) -> String? {
        let venue = root["venue"] as? [String: Any]
        let venueAddress = venue?["address"] as? [String: Any]
        let venueCountry = stringValue(venueAddress?["country"])
        let venueCity = stringValue(venueAddress?["city"])
        let displayName = stringValue(root["displayName"])
        let location = stringValue(root["location"])
        let teamAbbreviation = stringValue(root["abbreviation"])
        let sanitizedClubLocation = sanitizedCountryCandidate(
            location,
            teamName: displayName,
            teamAbbreviation: teamAbbreviation
        )
        let inferredLeagueCountry = teamCountryNameFromVenueReference(stringValue(venue?["$ref"]))
        let inferredNationalCountry = inferredNationalCountryName(
            displayName: displayName,
            location: location
        )
        let isNational = (root["isNational"] as? Bool) == true || inferredNationalCountry != nil

        if isNational {
            return inferredNationalCountry ?? location ?? displayName ?? venueCountry ?? inferredLeagueCountry
        }

        return resolvedClubCountryName(
            venueCountry: venueCountry,
            inferredLeagueCountry: inferredLeagueCountry,
            sanitizedClubLocation: sanitizedClubLocation,
            teamName: displayName,
            teamLocation: location,
            teamAbbreviation: teamAbbreviation,
            venueCity: venueCity
        )
    }

    static func resolvedTeamVenueLocationText(from root: [String: Any]) -> String? {
        let venue = root["venue"] as? [String: Any]
        let venueLocationText = venueLocationText(fromVenue: venue)
        guard let venueLocationText else { return nil }

        let displayName = stringValue(root["displayName"])
        let location = stringValue(root["location"])
        let inferredNationalCountry = inferredNationalCountryName(
            displayName: displayName,
            location: location
        )
        let isNational = (root["isNational"] as? Bool) == true || inferredNationalCountry != nil
        guard !isNational else { return venueLocationText }

        let venueAddress = venue?["address"] as? [String: Any]
        let venueCountry = stringValue(venueAddress?["country"])
        let venueCity = stringValue(venueAddress?["city"])
        let teamAbbreviation = stringValue(root["abbreviation"])
        let sanitizedClubLocation = sanitizedCountryCandidate(
            location,
            teamName: displayName,
            teamAbbreviation: teamAbbreviation
        )
        let inferredLeagueCountry = teamCountryNameFromVenueReference(stringValue(venue?["$ref"]))

        guard shouldTrustClubVenueCountry(
            venueCountry: venueCountry,
            inferredLeagueCountry: inferredLeagueCountry,
            sanitizedClubLocation: sanitizedClubLocation,
            teamName: displayName,
            teamLocation: location,
            teamAbbreviation: teamAbbreviation,
            venueCity: venueCity
        ) else {
            return nil
        }

        return venueLocationText
    }

    static func teamCountryNameFromVenueReference(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = raw.replacingOccurrences(of: "http://", with: "https://")
        guard let url = URL(string: normalized) else { return nil }

        let pathComponents = url.pathComponents
        guard let leaguesIndex = pathComponents.firstIndex(of: "leagues"),
              leaguesIndex + 1 < pathComponents.count else {
            return nil
        }

        let leagueSlug = pathComponents[leaguesIndex + 1].lowercased()
        let prefix = leagueSlug.split(separator: ".", maxSplits: 1).first.map(String.init) ?? leagueSlug
        return clubCountryByLeaguePrefix[prefix]
    }

    private static func fetchSummarySnapshot(
        competitionSlug: String,
        eventID: String,
        fallbackStartDate: Date,
        session: URLSession
    ) async -> SummarySnapshot? {
        guard !competitionSlug.isEmpty,
              !eventID.isEmpty,
              var components = URLComponents(
                  url: URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/\(competitionSlug)/summary")!,
                  resolvingAgainstBaseURL: false
              ) else {
            return nil
        }

        components.queryItems = [URLQueryItem(name: "event", value: eventID)]
        guard let url = components.url else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = Self.requestTimeout
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }

            let root = try jsonDictionary(from: data)
            guard let header = root["header"] as? [String: Any],
                  let competition = (header["competitions"] as? [[String: Any]])?.first else {
                return nil
            }

            let status = competition["status"] as? [String: Any]
            let statusType = status?["type"] as? [String: Any]
            let rawState = matchStatusState(from: stringValue(statusType?["state"]))
            let statusText = preferredStatusText(
                shortDetail: stringValue(statusType?["shortDetail"]),
                detail: stringValue(statusType?["detail"]),
                displayClock: stringValue(status?["displayClock"])
            )
            let statusDetailText = supplementalStatusText(
                preferredStatusText: statusText,
                detail: stringValue(statusType?["detail"]),
                displayClock: stringValue(status?["displayClock"])
            )
            let statusPeriod = intValue(statusType?["period"]) ?? intValue(status?["period"])
            let competitors = competition["competitors"] as? [[String: Any]] ?? []
            let home = competitors.first(where: { stringValue($0["homeAway"])?.lowercased() == "home" })
            let away = competitors.first(where: { stringValue($0["homeAway"])?.lowercased() == "away" })
            let competitionNote = competitionNoteText(from: competition)
            let locationText = summaryVenueLocationText(from: root, competition: competition)
            let actualStartDate = actualKickoffDate(from: root, fallbackStartDate: fallbackStartDate)

            let inferred = inferredKickoffStatusIfNeeded(
                from: rawState,
                statusText: statusText,
                startDate: fallbackStartDate
            )
            let cards = cardCounts(from: root)

            return SummarySnapshot(
                statusState: inferred.state,
                statusText: inferred.statusText,
                statusDetailText: statusDetailText,
                statusPeriod: statusPeriod,
                statusReliability: inferred.statusReliability,
                competitionNote: competitionNote,
                locationText: locationText,
                actualStartDate: actualStartDate,
                homeScore: (inferred.inferred && inferred.state == .inProgress) ? "0" : (stringValue(home?["score"]) ?? "0"),
                awayScore: (inferred.inferred && inferred.state == .inProgress) ? "0" : (stringValue(away?["score"]) ?? "0"),
                homeYellowCards: cards.homeYellowCards,
                awayYellowCards: cards.awayYellowCards,
                homeRedCards: cards.homeRedCards,
                awayRedCards: cards.awayRedCards
            )
        } catch {
            return nil
        }
    }

    static func matchGoalScorers(from root: [String: Any], match: FootballFixtureMatch) -> FootballMatchGoalScorers? {
        guard match.totalGoals > 0 else { return nil }
        guard match.statusState != .scheduled else { return nil }

        let competitors = ((root["header"] as? [String: Any])?["competitions"] as? [[String: Any]])?
            .first?["competitors"] as? [[String: Any]] ?? []

        let homeCompetitor = competitors.first(where: { Self.stringValue($0["homeAway"])?.lowercased() == "home" })
        let awayCompetitor = competitors.first(where: { Self.stringValue($0["homeAway"])?.lowercased() == "away" })

        let homeTeam = homeCompetitor?["team"] as? [String: Any] ?? [:]
        let awayTeam = awayCompetitor?["team"] as? [String: Any] ?? [:]
        let homeTeamID = stringValue(homeTeam["id"]) ?? stringValue(homeCompetitor?["id"]) ?? match.homeTeam.id
        let awayTeamID = stringValue(awayTeam["id"]) ?? stringValue(awayCompetitor?["id"]) ?? match.awayTeam.id
        let homeTeamName = stringValue(homeTeam["displayName"])
            ?? stringValue(homeTeam["shortDisplayName"])
            ?? match.homeTeam.name
        let awayTeamName = stringValue(awayTeam["displayName"])
            ?? stringValue(awayTeam["shortDisplayName"])
            ?? match.awayTeam.name

        let keyEvents = ((root["keyEvents"] as? [[String: Any]]) ?? [])
            + ((root["scoringPlays"] as? [[String: Any]]) ?? [])
        var homeScorers: [FootballMatchGoalScorer] = []
        var awayScorers: [FootballMatchGoalScorer] = []
        var seenEventSignatures = Set<String>()

        for (index, event) in keyEvents.enumerated() {
            guard isGoalScoringEvent(event) else { continue }
            guard let scorerName = goalScorerName(from: event), !scorerName.isEmpty else { continue }

            let minute = goalEventMinute(from: event)
            let teamID = stringValue((event["team"] as? [String: Any])?["id"])
            let signature = "\(teamID ?? "unknown")|\(minute ?? "n/a")|\(stringValue(event["text"]) ?? scorerName)"
            guard seenEventSignatures.insert(signature).inserted else { continue }
            let scorer = FootballMatchGoalScorer(
                id: "\(teamID ?? "unknown")-\(minute ?? "n/a")-\(index)",
                name: scorerName,
                minute: minute
            )

            if let teamID, teamID == homeTeamID {
                homeScorers.append(scorer)
                continue
            }
            if let teamID, teamID == awayTeamID {
                awayScorers.append(scorer)
                continue
            }

            let text = stringValue(event["text"]) ?? ""
            if text.localizedCaseInsensitiveContains("(\(homeTeamName))") {
                homeScorers.append(scorer)
            } else if text.localizedCaseInsensitiveContains("(\(awayTeamName))") {
                awayScorers.append(scorer)
            }
        }

        guard !homeScorers.isEmpty || !awayScorers.isEmpty else { return nil }
        return FootballMatchGoalScorers(home: homeScorers, away: awayScorers)
    }

    static func matchStatistics(from root: [String: Any]) -> [FootballMatchStatistic] {
        guard let teams = (root["boxscore"] as? [String: Any])?["teams"] as? [[String: Any]], !teams.isEmpty else {
            return []
        }

        guard let home = teams.first(where: { Self.stringValue($0["homeAway"])?.lowercased() == "home" }),
              let away = teams.first(where: { Self.stringValue($0["homeAway"])?.lowercased() == "away" }) else {
            return []
        }

        let homeStats = Self.teamStatisticsMap(from: home)
        let awayStats = Self.teamStatisticsMap(from: away)
        let homeTeamID = teamIdentifier(from: home)
        let awayTeamID = teamIdentifier(from: away)
        let substitutions = substitutionCountsByTeam(from: root["keyEvents"] as? [[String: Any]] ?? [])
        let homeSubstitutions = homeTeamID.flatMap { substitutions[$0] } ?? 0
        let awaySubstitutions = awayTeamID.flatMap { substitutions[$0] } ?? 0

        if homeStats.isEmpty && awayStats.isEmpty && homeSubstitutions == 0 && awaySubstitutions == 0 {
            return []
        }

        return Self.mergeStatistics(
            home: homeStats,
            away: awayStats,
            homeSubstitutions: homeSubstitutions,
            awaySubstitutions: awaySubstitutions
        )
    }

    static func actualKickoffDate(from root: [String: Any], fallbackStartDate: Date) -> Date? {
        let keyEvents = root["keyEvents"] as? [[String: Any]] ?? []
        let kickoffDates = keyEvents.compactMap { event -> Date? in
            let typeText = stringValue((event["type"] as? [String: Any])?["text"])?.lowercased()
            let typeValue = stringValue((event["type"] as? [String: Any])?["type"])?.lowercased()
            guard typeText == "kickoff" || typeValue == "kickoff" else { return nil }
            guard let wallclock = stringValue(event["wallclock"]) else { return nil }
            return parseEventDate(wallclock)
        }

        guard let actualKickoff = kickoffDates.min() else { return nil }

        let earliestAllowed = fallbackStartDate.addingTimeInterval(-15 * 60)
        let latestAllowed = fallbackStartDate.addingTimeInterval(2 * 60 * 60)
        guard actualKickoff >= earliestAllowed, actualKickoff <= latestAllowed else {
            return nil
        }

        return actualKickoff
    }

    private static func isGoalScoringEvent(_ event: [String: Any]) -> Bool {
        if (event["scoringPlay"] as? Bool) == true { return true }
        guard let typeText = stringValue((event["type"] as? [String: Any])?["text"])?.lowercased() else {
            return false
        }
        return typeText.contains("goal")
            || typeText.contains("penalty - scored")
            || typeText.contains("penalty scored")
    }

    private static func goalEventMinute(from event: [String: Any]) -> String? {
        let clock = (event["clock"] as? [String: Any])?["displayValue"]
        guard let minute = stringValue(clock)?.trimmingCharacters(in: .whitespacesAndNewlines), !minute.isEmpty else {
            return nil
        }
        return minute
    }

    private static func goalScorerName(from event: [String: Any]) -> String? {
        if let text = stringValue(event["text"]),
           let ownGoalScorer = ownGoalScorerName(from: text) {
            return "\(ownGoalScorer) (OG)"
        }

        if let athletes = event["athletesInvolved"] as? [[String: Any]],
           let athlete = athletes.first,
           let displayName = stringValue(athlete["displayName"]),
           !displayName.isEmpty {
            return displayName
        }

        guard let text = stringValue(event["text"]), !text.isEmpty else { return nil }
        let components = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
        guard components.count >= 2 else { return nil }

        let detail = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty { return nil }

        let ownGoalPrefix = "own goal by "
        if detail.lowercased().hasPrefix(ownGoalPrefix) {
            let remainder = String(detail.dropFirst(ownGoalPrefix.count))
            let untilParen = remainder.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: true).first
            let name = untilParen?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (name?.isEmpty == false) ? name : nil
        }

        if let range = detail.range(of: " (") {
            let candidate = detail[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            return candidate.isEmpty ? nil : candidate
        }

        return nil
    }

    private static func ownGoalScorerName(from text: String) -> String? {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return nil }

        let lowercasedText = normalizedText.lowercased()
        guard let ownGoalRange = lowercasedText.range(of: "own goal by ") else { return nil }

        let originalStart = normalizedText.index(
            normalizedText.startIndex,
            offsetBy: lowercasedText.distance(from: lowercasedText.startIndex, to: ownGoalRange.upperBound)
        )
        let remainder = String(normalizedText[originalStart...])

        let firstSentence = remainder
            .split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? remainder

        let candidate = firstSentence
            .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .split(separator: "(", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let candidate, !candidate.isEmpty else { return nil }
        return candidate
    }

    private static func liveMatch(
        from event: [String: Any],
        competitionSlug: String,
        competitionName: String,
        competitionStage: String?,
        competitionLogoURL: URL?
    ) -> FootballFixtureMatch? {
        guard let startDate = parsedEventDate(from: event),
              let competition = (event["competitions"] as? [[String: Any]])?.first else {
            return nil
        }

        let status = competition["status"] as? [String: Any]
        let statusType = status?["type"] as? [String: Any]
        let rawState = matchStatusState(from: stringValue(statusType?["state"]))
        let statusText = preferredStatusText(
            shortDetail: stringValue(statusType?["shortDetail"]),
            detail: stringValue(statusType?["detail"]),
            displayClock: stringValue(status?["displayClock"])
        )
        let statusDetailText = supplementalStatusText(
            preferredStatusText: statusText,
            detail: stringValue(statusType?["detail"]),
            displayClock: stringValue(status?["displayClock"])
        )
        let statusPeriod = intValue(statusType?["period"]) ?? intValue(status?["period"])
        let inferred = inferredKickoffStatusIfNeeded(
            from: rawState,
            statusText: statusText,
            startDate: startDate
        )

        guard let competitors = competition["competitors"] as? [[String: Any]],
              let home = competitors.first(where: { stringValue($0["homeAway"])?.lowercased() == "home" }),
              let away = competitors.first(where: { stringValue($0["homeAway"])?.lowercased() == "away" })
        else {
            return nil
        }

        let homeTeam = home["team"] as? [String: Any] ?? [:]
        let awayTeam = away["team"] as? [String: Any] ?? [:]
        let homeSummary = FootballTeamSummary(
            id: stringValue(homeTeam["id"]) ?? stringValue(home["id"]) ?? UUID().uuidString,
            name: teamName(from: homeTeam),
            abbreviation: teamAbbreviation(from: homeTeam, fallbackName: teamName(from: homeTeam)),
            logoURL: teamLogoURL(from: homeTeam),
            countryName: nil,
            isNational: false
        )
        let awaySummary = FootballTeamSummary(
            id: stringValue(awayTeam["id"]) ?? stringValue(away["id"]) ?? UUID().uuidString,
            name: teamName(from: awayTeam),
            abbreviation: teamAbbreviation(from: awayTeam, fallbackName: teamName(from: awayTeam)),
            logoURL: teamLogoURL(from: awayTeam),
            countryName: nil,
            isNational: false
        )

        let eventID = stringValue(event["id"]) ?? stringValue(competition["id"]) ?? UUID().uuidString
        let locationText = venueLocationText(from: competition)
        let seasonSlug = stringValue((event["season"] as? [String: Any])?["slug"])
            ?? stringValue((competition["season"] as? [String: Any])?["slug"])
        let competitionNote = competitionNoteText(from: competition)

        return FootballFixtureMatch(
            id: eventID,
            competitionSlug: competitionSlug,
            competitionName: competitionName,
            competitionStage: competitionStage,
            seasonSlug: seasonSlug,
            competitionNote: competitionNote,
            competitionLogoURL: competitionLogoURL,
            locationText: locationText,
            startDate: startDate,
            statusState: inferred.state,
            statusText: inferred.statusText,
            statusDetailText: statusDetailText,
            statusPeriod: statusPeriod,
            statusReliability: inferred.statusReliability,
            homeTeam: homeSummary,
            awayTeam: awaySummary,
            homeScore: (inferred.inferred && inferred.state == .inProgress) ? "0" : (stringValue(home["score"]) ?? "0"),
            awayScore: (inferred.inferred && inferred.state == .inProgress) ? "0" : (stringValue(away["score"]) ?? "0"),
            homeYellowCards: 0,
            awayYellowCards: 0,
            homeRedCards: 0,
            awayRedCards: 0
        )
    }

    private static func cardCounts(from root: [String: Any]) -> (homeYellowCards: Int, awayYellowCards: Int, homeRedCards: Int, awayRedCards: Int) {
        let teams = ((root["boxscore"] as? [String: Any])?["teams"] as? [[String: Any]]) ?? []
        let home = teams.first(where: { stringValue($0["homeAway"])?.lowercased() == "home" })
        let away = teams.first(where: { stringValue($0["homeAway"])?.lowercased() == "away" })

        return (
            homeYellowCards: statisticValue(named: "yellowCards", from: home),
            awayYellowCards: statisticValue(named: "yellowCards", from: away),
            homeRedCards: statisticValue(named: "redCards", from: home),
            awayRedCards: statisticValue(named: "redCards", from: away)
        )
    }

    private static func teamStatisticsMap(from entry: [String: Any]) -> [String: (label: String, value: String)] {
        let raw = entry["statistics"] as? [[String: Any]] ?? []
        var mapped: [String: (label: String, value: String)] = [:]
        for stat in raw {
            guard let name = stringValue(stat["name"])?.lowercased() else { continue }
            guard let value = stringValue(stat["displayValue"]) else { continue }
            let label = stringValue(stat["label"]) ?? name
            mapped[name] = (label: label, value: value)
        }
        return mapped
    }

    private static func mergeStatistics(
        home: [String: (label: String, value: String)],
        away: [String: (label: String, value: String)],
        homeSubstitutions: Int,
        awaySubstitutions: Int
    ) -> [FootballMatchStatistic] {
        let preferred: [(name: String, label: String)] = [
            ("possessionpct", "Possession"),
            ("totalshots", "Shots"),
            ("shotsontarget", "Shots On Target"),
            ("woncorners", "Corner Kicks"),
            ("offsides", "Offsides"),
            ("foulscommitted", "Fouls"),
            ("yellowcards", "Yellow Cards"),
            ("redcards", "Red Cards"),
            ("saves", "Saves"),
        ]

        var merged: [FootballMatchStatistic] = []
        for item in preferred {
            let homeValue = formatStatisticValue(name: item.name, rawValue: home[item.name]?.value ?? "--")
            let awayValue = formatStatisticValue(name: item.name, rawValue: away[item.name]?.value ?? "--")
            merged.append(
                FootballMatchStatistic(
                    id: item.name,
                    label: item.label,
                    homeValue: homeValue,
                    awayValue: awayValue
                )
            )
        }

        merged.append(
            FootballMatchStatistic(
                id: "substitutions",
                label: "Substitutions",
                homeValue: "\(homeSubstitutions)",
                awayValue: "\(awaySubstitutions)"
            )
        )
        return merged
    }

    private static func teamIdentifier(from entry: [String: Any]) -> String? {
        let team = entry["team"] as? [String: Any] ?? [:]
        return stringValue(team["id"])
    }

    private static func substitutionCountsByTeam(from keyEvents: [[String: Any]]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for event in keyEvents {
            let type = ((event["type"] as? [String: Any])?["type"] as? String)?.lowercased() ?? ""
            guard type.contains("substitution") else { continue }
            guard let teamID = stringValue((event["team"] as? [String: Any])?["id"]) else { continue }
            counts[teamID, default: 0] += 1
        }
        return counts
    }

    private static func formatStatisticValue(name: String, rawValue: String) -> String {
        if rawValue == "--" {
            return rawValue
        }
        if name == "possessionpct" {
            return rawValue.contains("%") ? rawValue : "\(rawValue)%"
        }
        return rawValue
    }

    private static func statisticValue(named name: String, from teamBoxscore: [String: Any]?) -> Int {
        let statistics = teamBoxscore?["statistics"] as? [[String: Any]] ?? []
        guard let entry = statistics.first(where: { stringValue($0["name"])?.caseInsensitiveCompare(name) == .orderedSame }) else {
            return 0
        }

        if let numericValue = intValue(entry["value"]) {
            return numericValue
        }

        return intValue(entry["displayValue"]) ?? 0
    }

    private static func matchStatusState(from raw: String?) -> FootballFixtureStatusState {
        switch raw?.lowercased() {
        case "pre":
            return .scheduled
        case "in":
            return .inProgress
        case "post":
            return .finished
        default:
            return .unknown
        }
    }

    static func preferredStatusText(
        shortDetail: String?,
        detail: String?,
        displayClock: String?
    ) -> String {
        let resolvedShortDetail = shortDetail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDisplayClock = displayClock?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let resolvedShortDetail, !resolvedShortDetail.isEmpty {
            if let resolvedDetail,
               statusTextShouldPreferDetail(shortDetail: resolvedShortDetail, detail: resolvedDetail) {
                return resolvedDetail
            }

            return resolvedShortDetail
        }

        if let resolvedDetail, !resolvedDetail.isEmpty {
            return resolvedDetail
        }

        if let resolvedDisplayClock, !resolvedDisplayClock.isEmpty {
            return resolvedDisplayClock
        }

        return "LIVE"
    }

    static func supplementalStatusText(
        preferredStatusText: String,
        detail: String?,
        displayClock: String?
    ) -> String? {
        let candidates = [
            detail?.trimmingCharacters(in: .whitespacesAndNewlines),
            displayClock?.trimmingCharacters(in: .whitespacesAndNewlines),
        ]

        for candidate in candidates {
            guard let candidate, !candidate.isEmpty else { continue }
            if normalizedStatusToken(candidate) != normalizedStatusToken(preferredStatusText) {
                return candidate
            }
        }

        return nil
    }

    private static func inferredKickoffStatusIfNeeded(
        from state: FootballFixtureStatusState,
        statusText: String,
        startDate: Date
    ) -> (
        state: FootballFixtureStatusState,
        statusText: String,
        statusReliability: FootballFixtureStatusReliability,
        inferred: Bool
    ) {
        let secondsFromKickoff = Date().timeIntervalSince(startDate)
        guard secondsFromKickoff >= 0 else {
            return (state, statusText, .reported, false)
        }

        guard state == .scheduled else {
            return (state, statusText, .reported, false)
        }

        if statusTextShouldRemainAsReported(statusText) {
            return (state, statusText, .reported, false)
        }

        let reliability: FootballFixtureStatusReliability
        if secondsFromKickoff >= delayedLiveDataWarningAfterKickoff {
            reliability = .delayedLiveData
        } else {
            reliability = .awaitingLiveData
        }

        return (.scheduled, "Starting soon", reliability, true)
    }

    private static func statusTextShouldRemainAsReported(_ statusText: String) -> Bool {
        FootballStatusText.indicatesInterruptedPlay(normalizedStatusToken(statusText))
    }

    private static func statusTextShouldPreferDetail(shortDetail: String, detail: String) -> Bool {
        let normalizedShort = normalizedStatusToken(shortDetail)
        let normalizedDetail = normalizedStatusToken(detail)

        if normalizedDetail.isEmpty || normalizedShort == normalizedDetail {
            return false
        }

        if FootballStatusText.indicatesInterruptedPlay(normalizedShort) {
            return false
        }

        if FootballStatusText.indicatesInterruptedPlay(normalizedDetail)
            && !FootballStatusText.indicatesInterruptedPlay(normalizedShort) {
            return true
        }

        if statusTextLooksLikeMinute(detail) && !statusTextLooksLikeMinute(shortDetail) {
            return true
        }

        let preciseTokens = ["FT", "HT", "ET", "AET", "PEN", "PK", "PENALTY", "EXTRA TIME"]
        let detailIsPrecise = preciseTokens.contains { normalizedDetail.contains($0) }
        let shortIsPrecise = preciseTokens.contains { normalizedShort.contains($0) }

        return detailIsPrecise && !shortIsPrecise
    }

    private static func statusTextLooksLikeMinute(_ text: String) -> Bool {
        let pattern = #"\d{1,3}(?:\+\d{1,2})?\s*'"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func normalizedStatusToken(_ text: String) -> String {
        FootballStatusText.normalized(text)
    }

    static func parseEventDate(_ rawDate: String) -> Date? {
        let formatterWithFraction = ISO8601DateFormatter()
        formatterWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatterWithFraction.date(from: rawDate) {
            return value
        }

        let formatterWithSeconds = gregorianPOSIXDateFormatter("yyyy-MM-dd'T'HH:mm:ssX")
        if let value = formatterWithSeconds.date(from: rawDate) {
            return value
        }

        let formatterWithoutSeconds = gregorianPOSIXDateFormatter("yyyy-MM-dd'T'HH:mmX")
        return formatterWithoutSeconds.date(from: rawDate)
    }

    private static func gregorianPOSIXDateFormatter(_ dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = dateFormat
        return formatter
    }

    private static func parsedEventDate(from event: [String: Any]) -> Date? {
        guard let rawDate = stringValue(event["date"]) else { return nil }
        return parseEventDate(rawDate)
    }

    private static func displayLeagueName(from rawSlug: String) -> String {
        rawSlug
            .replacingOccurrences(
                of: #"^\d{4}-\d{2}-"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private static func competitionDisplayName(from league: [String: Any]?) -> String? {
        stringValue(league?["name"])
    }

    private static func leagueStageName(from league: [String: Any]?) -> String? {
        let season = league?["season"] as? [String: Any]
        let type = season?["type"] as? [String: Any]
        return stringValue(type?["name"])
            ?? stringValue(type?["abbreviation"])
            ?? stringValue(season?["displayName"])
    }

    private static func leagueLogoURL(from league: [String: Any]?) -> URL? {
        let logos = league?["logos"] as? [[String: Any]] ?? []
        if let preferred = logos.first(where: { (($0["rel"] as? [String]) ?? []).contains("default") }),
           let href = safeURL(from: stringValue(preferred["href"])) {
            return href
        }
        return logos.first.flatMap { safeURL(from: stringValue($0["href"])) }
    }

    private static func teamName(from team: [String: Any]) -> String {
        stringValue(team["shortDisplayName"])
            ?? stringValue(team["displayName"])
            ?? stringValue(team["name"])
            ?? "Unknown"
    }

    private static func competitionNoteText(from competition: [String: Any]) -> String? {
        let notes = competition["notes"] as? [[String: Any]] ?? []
        for note in notes {
            if let value = stringValue(note["headline"])
                ?? stringValue(note["shortText"])
                ?? stringValue(note["text"])
                ?? stringValue(note["detail"]) {
                return value
            }
        }
        return nil
    }

    static func venueLocationText(from competition: [String: Any]) -> String? {
        venueLocationText(fromVenue: competition["venue"] as? [String: Any])
    }

    static func summaryVenueLocationText(from root: [String: Any], competition: [String: Any]) -> String? {
        let headerVenue = venueLocationText(from: competition)
        let gameInfoVenue = venueLocationText(
            fromVenue: ((root["gameInfo"] as? [String: Any])?["venue"] as? [String: Any])
        )

        return bestAvailableLocationText(
            reportedLocationText: gameInfoVenue,
            fallbackLocationText: headerVenue
        )
    }

    static func bestAvailableLocationText(
        reportedLocationText: String?,
        fallbackLocationText: String?
    ) -> String? {
        let normalizedReported = normalizedLocationTextValue(reportedLocationText)
        let normalizedFallback = normalizedLocationTextValue(fallbackLocationText)

        switch (normalizedReported, normalizedFallback) {
        case let (reported?, fallback?):
            if reported.caseInsensitiveCompare(fallback) == .orderedSame {
                return reported
            }
            return locationTextSpecificityScore(reported) >= locationTextSpecificityScore(fallback)
                ? reported
                : fallback
        case let (reported?, nil):
            return reported
        case let (nil, fallback?):
            return fallback
        case (nil, nil):
            return nil
        }
    }

    private static func venueLocationText(fromVenue venue: [String: Any]?) -> String? {
        let address = venue?["address"] as? [String: Any]
        let rawVenueName = stringValue(venue?["fullName"])

        // ESPN sometimes marks unknown venues as TBD/TBC while still attaching loose address data.
        // In those cases we prefer leaving the event location empty rather than storing a misleading placeholder.
        if let rawVenueName, isPlaceholderLocationText(rawVenueName) {
            return nil
        }

        let candidates = [
            rawVenueName,
            stringValue(address?["city"]),
            stringValue(address?["state"]),
            stringValue(address?["country"]),
        ]

        var components: [String] = []
        var seen = Set<String>()
        for candidate in candidates.compactMap(normalizedLocationTextValue) {
            let normalized = candidate.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard seen.insert(normalized).inserted else { continue }
            components.append(candidate)
        }

        guard !components.isEmpty else { return nil }
        return components.joined(separator: ", ")
    }

    private static func normalizedLocationTextValue(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPlaceholderLocationText(trimmed) else { return nil }
        return trimmed
    }

    private static func locationTextSpecificityScore(_ locationText: String) -> Int {
        let normalized = locationText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()

        let placeholderTokens = [
            "TBC",
            "TBD",
            "TO BE CONFIRMED",
            "TO BE ANNOUNCED",
            "VENUE TBC",
            "VENUE TBD",
        ]

        if placeholderTokens.contains(where: { normalized == $0 || normalized.contains($0) }) {
            return 0
        }

        let commaSeparatedParts = locationText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let wordCount = locationText
            .split(whereSeparator: \.isWhitespace)
            .count

        let aliasBonus = (locationText.contains("(") && locationText.contains(")")) ? 5 : 0
        return (commaSeparatedParts.count * 10) + wordCount + aliasBonus
    }

    private static func resolvedClubCountryName(
        venueCountry: String?,
        inferredLeagueCountry: String?,
        sanitizedClubLocation: String?,
        teamName: String?,
        teamLocation: String?,
        teamAbbreviation: String?,
        venueCity: String?
    ) -> String? {
        if let venueCountry,
           shouldTrustClubVenueCountry(
               venueCountry: venueCountry,
               inferredLeagueCountry: inferredLeagueCountry,
               sanitizedClubLocation: sanitizedClubLocation,
               teamName: teamName,
               teamLocation: teamLocation,
               teamAbbreviation: teamAbbreviation,
               venueCity: venueCity
           ) {
            return venueCountry
        }

        return inferredLeagueCountry ?? sanitizedClubLocation ?? venueCountry
    }

    private static func shouldTrustClubVenueCountry(
        venueCountry: String?,
        inferredLeagueCountry: String?,
        sanitizedClubLocation: String?,
        teamName: String?,
        teamLocation: String?,
        teamAbbreviation: String?,
        venueCity: String?
    ) -> Bool {
        guard let venueCountry = stringValue(venueCountry) else { return false }
        guard let inferredLeagueCountry = stringValue(inferredLeagueCountry) else { return true }

        if countryNamesMatch(venueCountry, inferredLeagueCountry) {
            return true
        }

        if let sanitizedClubLocation,
           countryNamesMatch(venueCountry, sanitizedClubLocation) {
            return true
        }

        if clubVenueMatchesIdentity(
            teamName: teamName,
            teamLocation: teamLocation,
            teamAbbreviation: teamAbbreviation,
            venueCity: venueCity,
            venueCountry: venueCountry
        ) {
            return true
        }

        return areRelatedBritishFootballCountries(venueCountry, inferredLeagueCountry)
    }

    private static func countryNamesMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        let normalizedLeft = normalizedCountryIdentityKey(lhs)
        let normalizedRight = normalizedCountryIdentityKey(rhs)

        guard !normalizedLeft.isEmpty, !normalizedRight.isEmpty else { return false }
        return normalizedLeft == normalizedRight
    }

    private static func areRelatedBritishFootballCountries(_ lhs: String?, _ rhs: String?) -> Bool {
        let normalizedLeft = normalizedCountryIdentityKey(lhs)
        let normalizedRight = normalizedCountryIdentityKey(rhs)

        guard !normalizedLeft.isEmpty, !normalizedRight.isEmpty else { return false }
        guard britishFootballCountries.contains(normalizedLeft),
              britishFootballCountries.contains(normalizedRight) else {
            return false
        }

        return true
    }

    private static func clubVenueMatchesIdentity(
        teamName: String?,
        teamLocation: String?,
        teamAbbreviation: String?,
        venueCity: String?,
        venueCountry: String?
    ) -> Bool {
        let identityTokens = clubIdentityTokens(
            teamName: teamName,
            teamLocation: teamLocation,
            teamAbbreviation: teamAbbreviation
        )
        guard !identityTokens.isEmpty else { return false }

        let localityTokens = locationIdentityTokens(venueCity).union(locationIdentityTokens(venueCountry))
        guard !localityTokens.isEmpty else { return false }
        return !identityTokens.isDisjoint(with: localityTokens)
    }

    private static func isPlaceholderLocationText(_ rawValue: String) -> Bool {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()

        guard !normalized.isEmpty else { return false }

        let compactWhitespace = normalized.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        let placeholderTokens = [
            "TBC",
            "TBD",
            "TO BE ANNOUNCED",
            "TO BE CONFIRMED",
            "TO BE DETERMINED",
            "VENUE TBC",
            "VENUE TBD",
            "VENUE TO BE ANNOUNCED",
            "VENUE TO BE CONFIRMED",
            "VENUE TO BE DETERMINED",
            "LOCATION TBC",
            "LOCATION TBD",
            "UNKNOWN",
        ]

        return placeholderTokens.contains(where: { token in
            compactWhitespace == token || compactWhitespace.contains(token)
        })
    }

    private static func teamAbbreviation(from team: [String: Any], fallbackName: String) -> String {
        stringValue(team["abbreviation"]) ?? String(fallbackName.prefix(3)).uppercased()
    }

    private static func teamLogoURL(from team: [String: Any]) -> URL? {
        if let direct = safeURL(from: stringValue(team["logo"])) {
            return direct
        }

        let logos = team["logos"] as? [[String: Any]] ?? []
        if let preferred = logos.first(where: { (($0["rel"] as? [String]) ?? []).contains("default") }),
           let href = safeURL(from: stringValue(preferred["href"])) {
            return href
        }

        return logos.first.flatMap { safeURL(from: stringValue($0["href"])) }
    }

    private static func stringValue(_ raw: Any?) -> String? {
        if let value = raw as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = raw as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int {
            return value
        }
        if let value = raw as? NSNumber {
            return value.intValue
        }
        if let value = stringValue(raw), let integer = Int(value) {
            return integer
        }
        if let value = stringValue(raw), let doubleValue = Double(value) {
            return Int(doubleValue)
        }
        return nil
    }

    private static func safeURL(from raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        let normalized = raw.replacingOccurrences(of: "http://", with: "https://")
        return URL(string: normalized)
    }

    private static func sanitizedCountryCandidate(
        _ raw: String?,
        teamName: String?,
        teamAbbreviation: String?
    ) -> String? {
        guard let candidate = stringValue(raw) else { return nil }
        let normalizedCandidate = normalizedLookupKey(candidate)

        if normalizedCandidate == normalizedLookupKey(teamName)
            || normalizedCandidate == normalizedLookupKey(teamAbbreviation) {
            return nil
        }

        return candidate
    }

    private static func inferredNationalCountryName(
        displayName: String?,
        location: String?
    ) -> String? {
        let displayKey = normalizedCountryIdentityKey(displayName)
        let locationKey = normalizedCountryIdentityKey(location)

        if !locationKey.isEmpty,
           locationKey == displayKey,
           recognizedCountryLookupKeys.contains(locationKey) {
            return stringValue(location) ?? stringValue(displayName)
        }

        if !locationKey.isEmpty, recognizedCountryLookupKeys.contains(locationKey) {
            return stringValue(location)
        }

        if !displayKey.isEmpty, recognizedCountryLookupKeys.contains(displayKey) {
            return stringValue(displayName)
        }

        return nil
    }

    private static func normalizedLookupKey(_ raw: String?) -> String {
        guard let raw = stringValue(raw) else { return "" }
        return raw
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .joined(separator: " ")
            .lowercased()
    }

    private static func normalizedCountryIdentityKey(_ raw: String?) -> String {
        let normalized = normalizedLookupKey(raw)
        guard !normalized.isEmpty else { return "" }
        return countryIdentityAliases[normalized] ?? normalized
    }

    private static func clubIdentityTokens(
        teamName: String?,
        teamLocation: String?,
        teamAbbreviation: String?
    ) -> Set<String> {
        locationIdentityTokens(teamName)
            .union(locationIdentityTokens(teamLocation))
            .subtracting(locationIdentityTokens(teamAbbreviation))
    }

    private static func locationIdentityTokens(_ raw: String?) -> Set<String> {
        let normalized = normalizedLookupKey(raw)
        guard !normalized.isEmpty else { return [] }
        return Set(
            normalized
                .split(separator: " ")
                .map(String.init)
                .filter { token in
                    token.count > 1 && !genericClubIdentityTokens.contains(token)
                }
        )
    }

    private static func jsonDictionary(from data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw NSError(domain: "FootballDataAPIClient", code: 1)
        }
        return dictionary
    }
}
