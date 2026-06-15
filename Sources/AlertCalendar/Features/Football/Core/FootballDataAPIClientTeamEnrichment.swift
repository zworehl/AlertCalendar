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
            actualEndDate: match.actualEndDate,
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
}
