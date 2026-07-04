import AppKit
import CoreLocation
import EventKit
import Foundation

extension CalendarMonitor {
    func footballMatchStatusText(_ match: FootballFixtureMatch) -> String {
        if match.statusReliability == .awaitingLiveData || match.statusReliability == .delayedLiveData {
            return "Starting soon"
        }

        switch match.statusState {
        case .inProgress:
            return match.statusText
        case .finished:
            return "FT"
        case .scheduled, .unknown:
            return Self.footballKickoffStatusText(for: match.startDate)
        }
    }

    func shouldRefreshFootballOnHeartbeat(now: Date) -> Bool {
        guard !managedFootballMatchIDs.isEmpty else {
            return false
        }

        let trackedMatches = managedFootballMatchIDs.compactMap { footballMatchesByID[$0] }
        let hasMissingTrackedMatches = trackedMatches.count < managedFootballMatchIDs.count
        return CalendarMonitorTime.hasElapsed(
            since: lastFootballManagedSyncDate,
            now: now,
            interval: Self.footballManagedRefreshInterval(
                for: trackedMatches,
                hasMissingTrackedMatches: hasMissingTrackedMatches,
                now: now
            )
        )
    }

    nonisolated static func footballManagedRefreshInterval(
        for matches: [FootballFixtureMatch],
        hasMissingTrackedMatches: Bool,
        now: Date
    ) -> TimeInterval {
        let matchInterval = footballRefreshInterval(for: matches, now: now)
        guard hasMissingTrackedMatches else { return matchInterval }
        return min(footballMissingCacheRefreshInterval, matchInterval)
    }

    nonisolated static func footballRefreshInterval(
        for matches: [FootballFixtureMatch],
        now: Date
    ) -> TimeInterval {
        guard !matches.isEmpty else { return footballUpcomingRefreshInterval }

        if matches.contains(where: { match in
            match.statusState == .inProgress
                || match.statusReliability == .awaitingLiveData
                || match.statusReliability == .delayedLiveData
        }) {
            return footballActiveRefreshInterval
        }

        if matches.contains(where: { match in
            let secondsFromKickoff = now.timeIntervalSince(match.startDate)
            return secondsFromKickoff >= -FootballDataAPIClient.summaryPreBufferBeforeKickoff
                && secondsFromKickoff <= FootballDataAPIClient.summaryPreBufferAfterKickoff
        }) {
            return footballManagedSyncInterval
        }

        if matches.contains(where: { match in
            match.statusState != .finished
                && match.startDate <= now.addingTimeInterval(24 * 60 * 60)
        }) {
            return footballUpcomingRefreshInterval
        }

        return footballIdleRefreshInterval
    }

    nonisolated static func footballManagedMatchIDsNeedingActualEndBackfill(
        _ matches: [FootballFixtureMatch],
        trackedMatchIDs: Set<String>,
        cachedMatchesByID: [String: FootballFixtureMatch]
    ) -> Set<String> {
        Set(
            matches.compactMap { match in
                guard trackedMatchIDs.contains(match.id) else { return nil }
                let cachedMatch = cachedMatchesByID[match.id]
                let knownActualEndDate = match.actualEndDate ?? cachedMatch?.actualEndDate
                guard knownActualEndDate == nil else { return nil }
                guard match.statusState == .finished || cachedMatch?.statusState == .finished else {
                    return nil
                }
                return match.id
            }
        )
    }

    func trackedFootballEvents(now: Date) -> [ManagedFootballEventSnapshot] {
        resolveManagedFootballEventSnapshots().filter { snapshot in
            let startDate = snapshot.event.startDate ?? snapshot.record.startDate
            return Self.isManagedFootballEventWithinSuggestionWindow(startDate: startDate, now: now)
        }
    }

    func resolveManagedFootballEventSnapshots() -> [ManagedFootballEventSnapshot] {
        if isManagedFootballSnapshotCacheValid {
            return cachedManagedFootballSnapshots
        }

        let deduplicatedRecords = deduplicatedManagedFootballEventRecords(managedFootballEventRecords)
        var resolvedSnapshots: [ManagedFootballEventSnapshot] = []
        var refreshedRecords: [ManagedFootballEventRecord] = []

        for record in deduplicatedRecords {
            guard let event = resolveManagedFootballEvent(for: record) else {
                continue
            }

            guard let refreshedRecord = managedFootballEventRecord(for: event, reference: record.reference) else {
                continue
            }
            refreshedRecords.append(refreshedRecord)
            resolvedSnapshots.append(
                ManagedFootballEventSnapshot(
                    event: event,
                    reference: refreshedRecord.reference,
                    record: refreshedRecord
                )
            )
        }

        persistManagedFootballEventRecords(refreshedRecords)
        cachedManagedFootballSnapshots = resolvedSnapshots
        isManagedFootballSnapshotCacheValid = true
        return resolvedSnapshots
    }

    func legacyManagedFootballEventSnapshots(
        now: Date,
        lookbackDays: Int,
        lookaheadDays: Int
    ) -> [ManagedFootballEventSnapshot] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -lookbackDays, to: now) ?? now
        let end = calendar.date(byAdding: .day, value: lookaheadDays, to: now) ?? now
        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: eventStore.calendars(for: .event)
        )

        return eventStore.events(matching: predicate).compactMap { event in
            guard let reference = ManagedFootballFixtureReference.parse(from: event.url) else { return nil }
            guard let record = managedFootballEventRecord(for: event, reference: reference) else { return nil }
            return ManagedFootballEventSnapshot(
                event: event,
                reference: reference,
                record: record
            )
        }
    }

    @discardableResult
    func removeManagedFootballEventsOutsideSuggestionWindow(now: Date) -> Int {
        var removedCount = 0
        var survivingRecords: [ManagedFootballEventRecord] = []

        for record in deduplicatedManagedFootballEventRecords(managedFootballEventRecords) {
            let resolvedEvent = resolveManagedFootballEvent(for: record)
            let effectiveStartDate = resolvedEvent?.startDate ?? record.startDate

            guard Self.isManagedFootballEventWithinSuggestionWindow(startDate: effectiveStartDate, now: now) else {
                if let resolvedEvent {
                    do {
                        try eventStore.remove(resolvedEvent, span: .thisEvent, commit: false)
                        removedCount += 1
                    } catch {
                        continue
                    }
                }
                continue
            }

            if let resolvedEvent,
               let survivingRecord = managedFootballEventRecord(for: resolvedEvent, reference: record.reference) {
                survivingRecords.append(survivingRecord)
            } else {
                survivingRecords.append(record)
            }
        }

        if removedCount > 0 {
            try? eventStore.commit()
        }

        persistManagedFootballEventRecords(survivingRecords)

        return removedCount
    }

    func deduplicatedFootballPresets(from competitionSlugs: [String]) -> [FootballCompetitionPreset] {
        var seen = Set<String>()
        return competitionSlugs.compactMap { slug in
            guard seen.insert(slug).inserted else { return nil }
            if let preset = FootballCompetitionPreset.menuPresets.first(where: { $0.slug == slug }) {
                return preset
            }
            return FootballCompetitionPreset(
                slug: slug,
                title: slug.replacingOccurrences(of: ".", with: " ").capitalized,
                lookbackDays: FootballCompetitionPreset.suggestionWindowLookbackDays,
                lookaheadDays: FootballCompetitionPreset.suggestionWindowLookaheadDays
            )
        }
    }

    @discardableResult
    func removeDuplicateManagedFootballEvents() -> Int {
        let deduplicatedRecords = deduplicatedManagedFootballEventRecords(managedFootballEventRecords)
        let removedCount = max(0, managedFootballEventRecords.count - deduplicatedRecords.count)
        persistManagedFootballEventRecords(deduplicatedRecords)
        return removedCount
    }

    func cacheFootballMatches(_ matches: [FootballFixtureMatch]) async {
        guard !matches.isEmpty else { return }
        let now = fixedSecondNow()
        let settings = snapshotSettings()
        for match in matches {
            if let previousMatch = footballMatchesByID[match.id],
               let goalHighlight = Self.goalHighlight(from: previousMatch, to: match, now: now) {
                activeFootballGoalHighlight = goalHighlight
                queueFootballGoalNotification(
                    for: match,
                    highlight: goalHighlight,
                    settings: settings
                )
            }
            if let previousMatch = footballMatchesByID[match.id] {
                queueFootballFinalNotificationIfNeeded(
                    from: previousMatch,
                    to: match,
                    settings: settings
                )
            }
            footballMatchesByID[match.id] = match
        }

        let teams = matches
            .flatMap { [$0.homeTeam, $0.awayTeam] }
            .reduce(into: [String: FootballTeamSummary]()) { partialResult, team in
                partialResult[team.id] = team
            }

        var teamLogoRequests: [(String, URL)] = []
        for team in teams.values {
            if team.isNational,
               let localFlagURL = FootballNationalLogoResolver.localFlagImageURL(
                   teamID: team.id,
                   name: team.name,
                   abbreviation: team.abbreviation,
                   countryName: team.countryName
               ) {
                let localPath = localFlagURL.path
                if footballLocalLogoPathsByTeamID[team.id] != localPath {
                    footballLocalLogoPathsByTeamID[team.id] = localPath
                }
                continue
            }

            guard let logoURL = team.logoURL else {
                continue
            }
            teamLogoRequests.append((team.id, logoURL))
        }
        let teamLogoPaths = await resolvedFootballLogoPaths(for: teamLogoRequests)
        for (teamID, path) in teamLogoPaths where footballLocalLogoPathsByTeamID[teamID] != path {
            footballLocalLogoPathsByTeamID[teamID] = path
        }

        let competitionLogoRequests = matches.compactMap { match -> (String, URL)? in
            guard let logoURL = match.competitionLogoURL else {
                return nil
            }
            return (match.competitionSlug, logoURL)
        }
        let competitionLogoPaths = await resolvedFootballLogoPaths(for: competitionLogoRequests)
        for (competitionSlug, path) in competitionLogoPaths where footballLocalLogoPathsByCompetitionSlug[competitionSlug] != path {
            footballLocalLogoPathsByCompetitionSlug[competitionSlug] = path
        }
    }

    func resolvedFootballLogoPaths(for requests: [(String, URL)]) async -> [String: String] {
        var seenIDs = Set<String>()
        let uniqueRequests = requests.filter { seenIDs.insert($0.0).inserted }
        guard !uniqueRequests.isEmpty else { return [:] }

        return await withTaskGroup(of: (String, String?).self) { group in
            for (id, url) in uniqueRequests {
                group.addTask { [footballImageStore] in
                    let localURL = await footballImageStore.localFileURL(for: url)
                    return (id, localURL?.path)
                }
            }

            var paths: [String: String] = [:]
            for await (id, path) in group {
                if let path {
                    paths[id] = path
                }
            }
            return paths
        }
    }

    func matchesPreservingKnownTimingContext(_ matches: [FootballFixtureMatch]) -> [FootballFixtureMatch] {
        matches.map { match in
            Self.footballMatchPreservingKnownTimingContext(
                match,
                previousMatch: footballMatchesByID[match.id]
            )
        }
    }

    nonisolated static func footballMatchPreservingKnownTimingContext(
        _ match: FootballFixtureMatch,
        previousMatch: FootballFixtureMatch?
    ) -> FootballFixtureMatch {
        guard let previousMatch, previousMatch.id == match.id else { return match }

        let actualStartDate = match.actualStartDate ?? previousMatch.actualStartDate
        let actualEndDate = match.actualEndDate ?? previousMatch.actualEndDate
        let locationText = FootballDataAPIClient.bestAvailableLocationText(
            reportedLocationText: match.locationText,
            fallbackLocationText: previousMatch.locationText
        )
        let statusDetailText = footballPreferredStatusDetailText(
            current: match.statusDetailText,
            fallback: previousMatch.statusDetailText
        )
        let statusPeriod = footballPreferredStatusPeriod(for: match, previousMatch: previousMatch)
        let homeTeam = match.homeTeam.withResolvedDetails(
            countryName: previousMatch.homeTeam.countryName,
            isNational: previousMatch.homeTeam.isNational,
            logoURL: previousMatch.homeTeam.logoURL
        )
        let awayTeam = match.awayTeam.withResolvedDetails(
            countryName: previousMatch.awayTeam.countryName,
            isNational: previousMatch.awayTeam.isNational,
            logoURL: previousMatch.awayTeam.logoURL
        )
        let outcomeProbabilities = match.outcomeProbabilities ?? previousMatch.outcomeProbabilities

        guard actualStartDate != match.actualStartDate
            || actualEndDate != match.actualEndDate
            || locationText != match.locationText
            || statusDetailText != match.statusDetailText
            || statusPeriod != match.statusPeriod
            || homeTeam != match.homeTeam
            || awayTeam != match.awayTeam
            || outcomeProbabilities != match.outcomeProbabilities else {
            return match
        }

        return FootballFixtureMatch(
            id: match.id,
            competitionSlug: match.competitionSlug,
            competitionName: match.competitionName,
            competitionStage: match.competitionStage,
            seasonSlug: match.seasonSlug,
            competitionNote: match.competitionNote,
            seriesSummary: match.seriesSummary,
            competitionLogoURL: match.competitionLogoURL,
            locationText: locationText,
            startDate: match.startDate,
            actualStartDate: actualStartDate,
            actualEndDate: actualEndDate,
            statusState: match.statusState,
            statusText: match.statusText,
            statusDetailText: statusDetailText,
            statusPeriod: statusPeriod,
            statusReliability: match.statusReliability,
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            homeScore: match.homeScore,
            awayScore: match.awayScore,
            homeYellowCards: match.homeYellowCards,
            awayYellowCards: match.awayYellowCards,
            homeRedCards: match.homeRedCards,
            awayRedCards: match.awayRedCards,
            outcomeProbabilities: outcomeProbabilities
        )
    }

    func cachedCompetitionMatches(for competition: FootballCompetitionPreset, now: Date) -> [FootballFixtureMatch] {
        Array(footballMatchesByID.values)
            .filter { $0.competitionSlug == competition.slug }
            .filter { match in
                Self.isManagedFootballEventWithinSuggestionWindow(startDate: match.startDate, now: now)
            }
            .map { match in
                (match: match, priority: Self.footballFixtureSortPriority(for: match, now: now))
            }
            .sorted { $0.priority < $1.priority }
            .map(\.match)
    }

    nonisolated static func defaultFootballCompetitionSection(for preset: FootballCompetitionPreset) -> FootballMenuCompetitionSection {
        return .placeholder(for: preset)
    }


}
