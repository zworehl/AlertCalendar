import AppKit
import CoreLocation
import EventKit
import Foundation

extension CalendarMonitor {
    func upcomingManagedFootballEventCount(now: Date) -> Int {
        trackedFootballEvents(now: now).reduce(into: Set<String>()) { matchIDs, snapshot in
            let startDate = snapshot.event.startDate ?? snapshot.record.startDate
            let endDate = snapshot.event.endDate ?? startDate
            if startDate > now || endDate > now {
                matchIDs.insert(snapshot.reference.matchID)
            }
        }
        .count
    }

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

        let lastManagedRefresh = lastFootballManagedSyncDate?.timeIntervalSince1970 ?? 0
        if lastManagedRefresh <= 0 {
            return true
        }

        return now.timeIntervalSince1970 - lastManagedRefresh >= Self.footballManagedSyncInterval
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

            let refreshedRecord = managedFootballEventRecord(for: event, reference: record.reference)
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
            return ManagedFootballEventSnapshot(
                event: event,
                reference: reference,
                record: managedFootballEventRecord(for: event, reference: reference)
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

            if let resolvedEvent {
                survivingRecords.append(managedFootballEventRecord(for: resolvedEvent, reference: record.reference))
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
        for match in matches {
            if let previousMatch = footballMatchesByID[match.id],
               let goalHighlight = Self.goalHighlight(from: previousMatch, to: match, now: now) {
                activeFootballGoalHighlight = goalHighlight
            }
            footballMatchesByID[match.id] = match
        }

        let teams = matches
            .flatMap { [$0.homeTeam, $0.awayTeam] }
            .reduce(into: [String: FootballTeamSummary]()) { partialResult, team in
                partialResult[team.id] = team
            }

        for team in teams.values {
            guard footballLocalLogoPathsByTeamID[team.id] == nil else { continue }
            guard let localLogo = await footballImageStore.localFileURL(for: team.logoURL) else { continue }
            footballLocalLogoPathsByTeamID[team.id] = localLogo.path
        }

        for match in matches {
            guard footballLocalLogoPathsByCompetitionSlug[match.competitionSlug] == nil else { continue }
            guard let localLogo = await footballImageStore.localFileURL(for: match.competitionLogoURL) else { continue }
            footballLocalLogoPathsByCompetitionSlug[match.competitionSlug] = localLogo.path
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
        let statusDetailText = footballPreferredStatusDetailText(
            current: match.statusDetailText,
            fallback: previousMatch.statusDetailText
        )
        let statusPeriod = footballPreferredStatusPeriod(for: match, previousMatch: previousMatch)

        guard actualStartDate != match.actualStartDate
            || statusDetailText != match.statusDetailText
            || statusPeriod != match.statusPeriod else {
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
            locationText: match.locationText,
            startDate: match.startDate,
            actualStartDate: actualStartDate,
            statusState: match.statusState,
            statusText: match.statusText,
            statusDetailText: statusDetailText,
            statusPeriod: statusPeriod,
            statusReliability: match.statusReliability,
            homeTeam: match.homeTeam,
            awayTeam: match.awayTeam,
            homeScore: match.homeScore,
            awayScore: match.awayScore,
            homeYellowCards: match.homeYellowCards,
            awayYellowCards: match.awayYellowCards,
            homeRedCards: match.homeRedCards,
            awayRedCards: match.awayRedCards
        )
    }

    func cachedCompetitionMatches(for competition: FootballCompetitionPreset, now: Date) -> [FootballFixtureMatch] {
        Array(footballMatchesByID.values)
            .filter { $0.competitionSlug == competition.slug }
            .filter { match in
                Self.isManagedFootballEventWithinSuggestionWindow(startDate: match.startDate, now: now)
            }
            .sorted { lhs, rhs in
                Self.footballFixtureSortPriority(for: lhs, now: now) < Self.footballFixtureSortPriority(for: rhs, now: now)
            }
    }

    nonisolated static func defaultFootballCompetitionSection(for preset: FootballCompetitionPreset) -> FootballMenuCompetitionSection {
        return .placeholder(for: preset)
    }


}
