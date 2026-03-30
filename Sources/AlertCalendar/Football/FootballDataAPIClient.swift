import Foundation

actor FootballDataAPIClient {
    private struct TeamResponse {
        let countryName: String?
        let isNational: Bool
        let logoURL: URL?
    }

    private struct SummarySnapshot {
        let statusState: FootballFixtureStatusState
        let statusText: String
        let statusPeriod: Int?
        let statusReliability: FootballFixtureStatusReliability
        let competitionNote: String?
        let homeScore: String
        let awayScore: String
        let homeYellowCards: Int
        let awayYellowCards: Int
        let homeRedCards: Int
        let awayRedCards: Int
    }

    private let session: URLSession
    private var teamCache: [String: TeamResponse] = [:]
    private static let requestTimeout: TimeInterval = 8
    private static let resourceTimeout: TimeInterval = 20
    private static let summaryPreBufferBeforeKickoff: TimeInterval = 15 * 60
    private static let summaryPreBufferAfterKickoff: TimeInterval = 3 * 60 * 60
    private static let delayedLiveDataWarningAfterKickoff: TimeInterval = 15 * 60

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
            guard snapshot.statusState != match.statusState
                || snapshot.statusText != match.statusText
                || snapshot.statusPeriod != match.statusPeriod
                || snapshot.statusReliability != match.statusReliability
                || snapshot.competitionNote != match.competitionNote
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
                locationText: match.locationText,
                startDate: match.startDate,
                statusState: snapshot.statusState,
                statusText: snapshot.statusText,
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

            return FootballFixtureMatch(
                id: match.id,
                competitionSlug: match.competitionSlug,
                competitionName: match.competitionName,
                competitionStage: match.competitionStage,
                seasonSlug: match.seasonSlug,
                competitionNote: match.competitionNote,
                competitionLogoURL: match.competitionLogoURL,
                locationText: match.locationText,
                startDate: match.startDate,
                statusState: match.statusState,
                statusText: match.statusText,
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
            let venueCountry = stringValue(((root["venue"] as? [String: Any])?["address"] as? [String: Any])?["country"])
            let location = stringValue(root["location"])
            let isNational = (root["isNational"] as? Bool) == true
            let countryName = isNational ? (location ?? venueCountry) : (venueCountry ?? location)

            let logos = root["logos"] as? [[String: Any]] ?? []
            let preferredLogo = logos.first(where: { (($0["rel"] as? [String]) ?? []).contains("default") }) ?? logos.first

            return TeamResponse(
                countryName: countryName,
                isNational: isNational,
                logoURL: safeURL(from: stringValue(preferredLogo?["href"]))
            )
        } catch {
            return nil
        }
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
            let statusText = stringValue(statusType?["shortDetail"])
                ?? stringValue(statusType?["detail"])
                ?? stringValue(status?["displayClock"])
                ?? "LIVE"
            let statusPeriod = intValue(statusType?["period"]) ?? intValue(status?["period"])
            let competitors = competition["competitors"] as? [[String: Any]] ?? []
            let home = competitors.first(where: { stringValue($0["homeAway"])?.lowercased() == "home" })
            let away = competitors.first(where: { stringValue($0["homeAway"])?.lowercased() == "away" })
            let competitionNote = competitionNoteText(from: competition)

            let inferred = inferredKickoffStatusIfNeeded(
                from: rawState,
                statusText: statusText,
                startDate: fallbackStartDate
            )
            let cards = cardCounts(from: root)

            return SummarySnapshot(
                statusState: inferred.state,
                statusText: inferred.statusText,
                statusPeriod: statusPeriod,
                statusReliability: inferred.statusReliability,
                competitionNote: competitionNote,
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
        let statusText = stringValue(statusType?["shortDetail"])
            ?? stringValue(statusType?["detail"])
            ?? stringValue(status?["displayClock"])
            ?? "LIVE"
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
        let normalized = statusText
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()

        let preservedTokens = [
            "POSTPONED",
            "DELAYED",
            "CANCELED",
            "CANCELLED",
            "SUSPENDED",
            "ABANDONED",
        ]

        return preservedTokens.contains { normalized.contains($0) }
    }

    static func parseEventDate(_ rawDate: String) -> Date? {
        let formatterWithFraction = ISO8601DateFormatter()
        formatterWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatterWithFraction.date(from: rawDate) {
            return value
        }

        let formatterWithSeconds = DateFormatter()
        formatterWithSeconds.calendar = Calendar(identifier: .gregorian)
        formatterWithSeconds.locale = Locale(identifier: "en_US_POSIX")
        formatterWithSeconds.dateFormat = "yyyy-MM-dd'T'HH:mm:ssX"
        if let value = formatterWithSeconds.date(from: rawDate) {
            return value
        }

        let formatterWithoutSeconds = DateFormatter()
        formatterWithoutSeconds.calendar = Calendar(identifier: .gregorian)
        formatterWithoutSeconds.locale = Locale(identifier: "en_US_POSIX")
        formatterWithoutSeconds.dateFormat = "yyyy-MM-dd'T'HH:mmX"
        return formatterWithoutSeconds.date(from: rawDate)
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
        let venue = competition["venue"] as? [String: Any]
        let address = venue?["address"] as? [String: Any]

        let candidates = [
            stringValue(venue?["fullName"]),
            stringValue(address?["city"]),
            stringValue(address?["country"]),
        ]

        var components: [String] = []
        var seen = Set<String>()
        for candidate in candidates.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            guard !candidate.isEmpty else { continue }
            let normalized = candidate.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard seen.insert(normalized).inserted else { continue }
            components.append(candidate)
        }

        guard !components.isEmpty else { return nil }
        return components.joined(separator: ", ")
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

    private static func jsonDictionary(from data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw NSError(domain: "FootballDataAPIClient", code: 1)
        }
        return dictionary
    }
}
