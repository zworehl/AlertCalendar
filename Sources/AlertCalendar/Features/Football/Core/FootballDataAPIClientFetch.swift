import Foundation

extension FootballDataAPIClient {
    func enrichTeams(in matches: [FootballFixtureMatch]) async -> [FootballFixtureMatch] {
        let teamIDs = Set(matches.flatMap { [$0.homeTeam.id, $0.awayTeam.id] }.filter { !$0.isEmpty })
        guard !teamIDs.isEmpty else { return matches }

        let now = AlertCalendarClock.nowRoundedToSecond()
        let missingTeamIDs = teamIDs.filter { !hasFreshCachedTeam($0, now: now) }
        guard !missingTeamIDs.isEmpty else {
            return matches.map { match in
                Self.matchByApplyingCachedTeamDetails(
                    to: match,
                    cachedTeams: teamCache
                )
            }
        }

        let fetched = await withTaskGroup(of: (String, TeamResponse?).self) { group in
            for teamID in missingTeamIDs {
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
                teamCacheFetchedAt[teamID] = now
            }
            persistTeamCache()
        }

        return matches.map {
            Self.matchByApplyingCachedTeamDetails(
                to: $0,
                cachedTeams: teamCache
            )
        }
    }

    func hasFreshCachedTeam(_ teamID: String, now: Date) -> Bool {
        guard teamCache[teamID] != nil else { return false }
        guard let fetchedAt = teamCacheFetchedAt[teamID] else { return true }
        return now.timeIntervalSince(fetchedAt) <= Self.teamCacheTTL
    }

    func persistTeamCache() {
        guard let teamCacheStore else { return }

        let now = AlertCalendarClock.nowRoundedToSecond()
        var entries: [String: TeamCacheEntry] = [:]
        entries.reserveCapacity(teamCache.count)

        for (teamID, response) in teamCache {
            guard let fetchedAt = teamCacheFetchedAt[teamID],
                  now.timeIntervalSince(fetchedAt) <= Self.teamCacheTTL else {
                continue
            }
            entries[teamID] = TeamCacheEntry(
                response: response,
                fetchedAt: fetchedAt
            )
        }

        teamCacheStore.save(entries)
    }

    static func matchByApplyingCachedTeamDetails(
        to match: FootballFixtureMatch,
        cachedTeams: [String: TeamResponse]
    ) -> FootballFixtureMatch {
        let resolvedHome = cachedTeams[match.homeTeam.id]
        let resolvedAway = cachedTeams[match.awayTeam.id]
        let teamVenueFallback = shouldUseHomeTeamVenueFallback(for: match)
            ? resolvedHome?.venueLocationText
            : nil
        let resolvedLocationText = bestAvailableLocationText(
            reportedLocationText: match.locationText,
            fallbackLocationText: teamVenueFallback
        )

        return FootballFixtureMatch(
            id: match.id,
            competitionSlug: match.competitionSlug,
            competitionName: match.competitionName,
            competitionStage: match.competitionStage,
            seasonSlug: match.seasonSlug,
            competitionNote: match.competitionNote,
            seriesSummary: match.seriesSummary,
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

    static func shouldUseHomeTeamVenueFallback(for match: FootballFixtureMatch) -> Bool {
        match.competitionCategory == .clubCompetitions
    }

    func fetchMatchesForCompetition(_ competition: FootballCompetitionPreset) async -> [FootballFixtureMatch] {
        let calendar = Calendar(identifier: .gregorian)
        let now = AlertCalendarClock.nowRoundedToSecond()
        let dayStart = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -competition.lookbackDays, to: dayStart) ?? dayStart
        let end = calendar.date(byAdding: .day, value: competition.lookaheadDays, to: dayStart) ?? dayStart
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: end) ?? end.addingTimeInterval(24 * 60 * 60)

        async let primary = fetchMatchesForCompetitionPage(
            competition,
            dateRange: nil
        )
        async let ranged = fetchMatchesForCompetitionPage(
            competition,
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

    func fetchMatchesForCompetitionPage(
        _ competition: FootballCompetitionPreset,
        dateRange: (Date, Date)?
    ) async -> [FootballFixtureMatch] {
        guard let url = Self.scoreboardURL(
            slug: competition.slug,
            dateRange: dateRange
        ) else {
            return []
        }

        return await scoreboardMatchesPage(
            url: url,
            slug: competition.slug,
            competitionName: competition.title
        )
    }

    static func goalScorersCacheKey(for match: FootballFixtureMatch) -> String {
        let statusDetail = match.statusDetailText ?? ""
        let statusPeriod = match.statusPeriod.map(String.init) ?? "n/a"
        return "\(match.id)|\(match.homeScore)|\(match.awayScore)|\(match.statusText)|\(statusDetail)|\(statusPeriod)"
    }

    static func statisticsCacheKey(for match: FootballFixtureMatch) -> String {
        let statusPeriod = match.statusPeriod.map(String.init) ?? "n/a"
        return "\(match.id)|\(match.homeScore)|\(match.awayScore)|\(match.statusText)|\(statusPeriod)"
    }

    static func summaryRootCacheKey(url: URL, match: FootballFixtureMatch) -> String {
        let statusDetail = match.statusDetailText ?? ""
        let statusPeriod = match.statusPeriod.map(String.init) ?? "n/a"
        return "\(url.absoluteString)|\(match.id)|\(match.homeScore)|\(match.awayScore)|\(match.statusText)|\(match.statusState.rawValue)|\(statusDetail)|\(statusPeriod)"
    }

    static func summaryRoot(
        _ root: [String: Any],
        satisfies requirement: SummaryRootCacheRequirement,
        match: FootballFixtureMatch
    ) -> Bool {
        switch requirement {
        case .any:
            return true
        case .minimumScorerCount(let minimumCount):
            guard minimumCount > 0 else { return true }
            let scorers = matchGoalScorers(from: root, match: match)
            let scorerCount = (scorers?.home.count ?? 0) + (scorers?.away.count ?? 0)
            return scorerCount >= minimumCount
        case .hasStatistics:
            return !matchStatistics(from: root).isEmpty
        }
    }

    static func summaryURLs(for match: FootballFixtureMatch) -> [URL] {
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

    static func fetchSummaryRoot(
        url: URL,
        session: URLSession
    ) async throws -> [String: Any]? {
        guard let data = try await fetchSummaryData(url: url, session: session) else {
            return nil
        }
        return try jsonDictionary(from: data)
    }

    static func fetchSummaryData(
        url: URL,
        session: URLSession
    ) async throws -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.requestTimeout
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        return data
    }

    static func fetchMatchesPage(
        slug: String,
        competitionName: String,
        session: URLSession,
        dateRange: (Date, Date)?
    ) async -> [FootballFixtureMatch] {
        guard let url = scoreboardURL(slug: slug, dateRange: dateRange) else { return [] }
        return await fetchMatchesPage(
            url: url,
            slug: slug,
            competitionName: competitionName,
            session: session
        )
    }

    static func scoreboardURL(
        slug: String,
        dateRange: (Date, Date)?
    ) -> URL? {
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

        return components?.url
    }

    static func fetchMatchesPage(
        url: URL,
        slug: String,
        competitionName: String,
        session: URLSession
    ) async -> [FootballFixtureMatch] {
        do {
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

    static func fetchTeamDetails(teamID: String, session: URLSession) async -> TeamResponse? {
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

    static func fetchSummarySnapshot(
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
            guard let root = try await fetchSummaryRoot(url: url, session: session) else { return nil }
            return summarySnapshot(from: root, fallbackStartDate: fallbackStartDate)
        } catch {
            return nil
        }
    }

    func summarySnapshot(for match: FootballFixtureMatch) async -> SummarySnapshot? {
        for url in Self.summaryURLs(for: match) {
            do {
                guard let root = try await summaryRoot(url: url, match: match),
                      let snapshot = Self.summarySnapshot(from: root, fallbackStartDate: match.startDate) else {
                    continue
                }
                return snapshot
            } catch {
                continue
            }
        }

        return nil
    }

    static func summarySnapshot(
        from root: [String: Any],
        fallbackStartDate: Date
    ) -> SummarySnapshot? {
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
        let seriesSummary = seriesSummary(
            from: competition,
            homeCompetitor: home,
            awayCompetitor: away
        )
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
            seriesSummary: seriesSummary,
            locationText: locationText,
            actualStartDate: actualStartDate,
            homeScore: (inferred.inferred && inferred.state == .inProgress) ? "0" : (stringValue(home?["score"]) ?? "0"),
            awayScore: (inferred.inferred && inferred.state == .inProgress) ? "0" : (stringValue(away?["score"]) ?? "0"),
            homeYellowCards: cards.homeYellowCards,
            awayYellowCards: cards.awayYellowCards,
            homeRedCards: cards.homeRedCards,
            awayRedCards: cards.awayRedCards
        )
    }


}
