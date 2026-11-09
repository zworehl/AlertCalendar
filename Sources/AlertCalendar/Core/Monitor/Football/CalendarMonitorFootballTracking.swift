import AppKit
import CoreLocation
import EventKit
import Foundation
extension CalendarMonitor {
    func footballMatchStatusText(_ match: FootballFixtureMatch) -> String {
        if match.statusReliability == .awaitingLiveData || match.statusReliability == .delayedLiveData {
            return L10n.text("Starting soon")
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
            guard match.statusState == .finished,
                  let actualEndDate = match.actualEndDate else {
                return false
            }
            let secondsSinceFinal = now.timeIntervalSince(actualEndDate)
            return secondsSinceFinal >= 0
                && secondsSinceFinal <= footballPostMatchStabilizationWindow
        }) {
            return footballManagedSyncInterval
        }

        if matches.contains(where: { match in
            guard match.statusState == .scheduled || match.statusState == .unknown else {
                return false
            }
            let secondsFromKickoff = now.timeIntervalSince(match.startDate)
            return secondsFromKickoff >= -FootballDataAPIClient.summaryPreBufferBeforeKickoff
                && secondsFromKickoff <= footballKickoffGraceWindow
        }) {
            return footballManagedSyncInterval
        }

        if matches.contains(where: { match in
            let secondsFromKickoff = now.timeIntervalSince(match.startDate)
            if match.statusState == .finished, match.actualEndDate == nil {
                return secondsFromKickoff >= 0
                    && secondsFromKickoff <= FootballDataAPIClient.summaryPreBufferAfterKickoff
            }

            guard match.statusState == .scheduled || match.statusState == .unknown else { return false }
            let timeUntilKickoff = match.startDate.timeIntervalSince(now)
            let isApproaching = timeUntilKickoff > FootballDataAPIClient.summaryPreBufferBeforeKickoff
                && timeUntilKickoff <= footballApproachingKickoffWindow
            let isOverdue = secondsFromKickoff > footballKickoffGraceWindow
                && secondsFromKickoff <= FootballDataAPIClient.summaryPreBufferAfterKickoff
            return isApproaching || isOverdue
        }) {
            return footballApproachingRefreshInterval
        }

        if matches.contains(where: { match in
            match.statusState != .finished
                && match.startDate >= now
                && match.startDate <= now.addingTimeInterval(24 * 60 * 60)
        }) {
            return footballUpcomingRefreshInterval
        }

        let allFinishedMatchesAreSettled = matches.allSatisfy { match in
            guard match.statusState == .finished,
                  let actualEndDate = match.actualEndDate else {
                return false
            }
            return now.timeIntervalSince(actualEndDate) > footballPostMatchStabilizationWindow
        }
        if allFinishedMatchesAreSettled {
            return footballSettledRefreshInterval
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

    nonisolated static func footballManagedMatchIDsNeedingVenueBackfill(
        _ matches: [FootballFixtureMatch],
        trackedMatchIDs: Set<String>,
        cachedMatchesByID: [String: FootballFixtureMatch]
    ) -> Set<String> {
        Set(matches.compactMap { match in
            guard trackedMatchIDs.contains(match.id),
                  FootballCalendarLocation.resolvedText(
                      reported: match.locationText,
                      existing: cachedMatchesByID[match.id]?.locationText,
                      structuredTitle: nil
                  ) == nil else { return nil }
            return match.id
        })
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
                refreshedRecords.append(record)
                continue
            }

            guard let refreshedRecord = managedFootballEventRecord(for: event, reference: record.reference) else {
                refreshedRecords.append(record)
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
        performManagedFootballCleanup(now: now) ?? 0
    }

    /// Nil means the transaction failed; the caller must not advance its cadence.
    func performManagedFootballCleanup(now: Date) -> Int? {
        do {
            let result = try ManagedFootballMutationCoordinator.removeExpired(
                records: deduplicatedManagedFootballEventRecords(managedFootballEventRecords),
                now: now, mutations: calendarMutations, resolve: resolveManagedFootballEvent(for:),
                refreshedRecord: managedFootballEventRecord(for:reference:)
            )
            persistManagedFootballEventRecords(result.records)
            reportFootballCalendarMutation(source: "football.calendar-cleanup", error: nil)
            return result.removedCount
        } catch {
            reportFootballCalendarMutation(source: "football.calendar-cleanup", error: error)
            return nil
        }
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
                queueFootballDisallowedGoalNotificationIfNeeded(
                    from: previousMatch,
                    to: match,
                    settings: settings
                )
                queueFootballFinalNotificationIfNeeded(
                    from: previousMatch,
                    to: match,
                    settings: settings
                )
            }
            footballMatchesByID[match.id] = match
        }

        let cacheStart = now.addingTimeInterval(-60 * 24 * 60 * 60)
        let cacheEnd = now.addingTimeInterval(100 * 24 * 60 * 60)
        let preservedMatchIDs = managedFootballMatchIDs
        footballMatchesByID = footballMatchesByID.filter { matchID, match in
            preservedMatchIDs.contains(matchID)
                || (match.startDate >= cacheStart && match.startDate <= cacheEnd)
        }
        if let footballMatchCacheStore {
            let snapshot = FootballMatchCacheSnapshot(
                fetchedAt: now,
                matches: footballMatchesByID.values.sorted {
                    $0.startDate == $1.startDate ? $0.id < $1.id : $0.startDate < $1.startDate
                }
            )
            scheduleFootballMatchCacheWrite(snapshot, store: footballMatchCacheStore)
        }

        scheduleFootballLogoLoading(for: matches)
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
        let officialWinner = match.officialWinner ?? previousMatch.officialWinner
        let homeShootoutScore = match.homeShootoutScore ?? previousMatch.homeShootoutScore
        let awayShootoutScore = match.awayShootoutScore ?? previousMatch.awayShootoutScore
        let pregameOutcomeProbabilities = match.pregameOutcomeProbabilities
            ?? previousMatch.pregameOutcomeProbabilities
        let outcomeProbabilities: FootballMatchOutcomeProbabilities?
        if let probabilities = match.outcomeProbabilities {
            outcomeProbabilities = probabilities
        } else if previousMatch.outcomeProbabilities?.source == .liveMarketOdds {
            // The current scoreboard response succeeded but no longer exposes the
            // in-play market, so an older live quote must not survive the merge.
            outcomeProbabilities = nil
        } else {
            outcomeProbabilities = previousMatch.outcomeProbabilities
        }

        guard actualStartDate != match.actualStartDate
            || actualEndDate != match.actualEndDate
            || locationText != match.locationText
            || statusDetailText != match.statusDetailText
            || statusPeriod != match.statusPeriod
            || homeTeam != match.homeTeam
            || awayTeam != match.awayTeam
            || officialWinner != match.officialWinner
            || homeShootoutScore != match.homeShootoutScore
            || awayShootoutScore != match.awayShootoutScore
            || pregameOutcomeProbabilities != match.pregameOutcomeProbabilities
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
            officialWinner: officialWinner,
            homeShootoutScore: homeShootoutScore,
            awayShootoutScore: awayShootoutScore,
            pregameOutcomeProbabilities: pregameOutcomeProbabilities,
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
        .placeholder(for: preset)
    }
}
