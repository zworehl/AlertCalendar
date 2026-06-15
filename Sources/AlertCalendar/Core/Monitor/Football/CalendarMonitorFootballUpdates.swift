import AppKit
import CoreLocation
import EventKit
import Foundation

extension CalendarMonitor {
    func applyFootballEventUpdates(_ trackedEvents: [ManagedFootballEventSnapshot], using matches: [FootballFixtureMatch]) async {
        let matchesByID = Dictionary(uniqueKeysWithValues: matches.map { ($0.id, $0) })
        var hasPendingChanges = false
        var refreshedRecordsByReference = Dictionary(uniqueKeysWithValues: managedFootballEventRecords.map { ($0.reference, $0) })
        var updatedReferences: [ManagedFootballFixtureReference] = []

        for snapshot in trackedEvents {
            guard let match = matchesByID[snapshot.reference.matchID] else { continue }
            let updatedTitle = FootballFixtureFormatter.calendarTitle(for: match)
            let updatedLocation = match.locationText
            let updatedStartDate = Self.footballEffectiveStartDate(for: match)
            let updatedEndDate = approximateEndDate(for: match)
            let needsStructuredLocationUpdate = await footballStructuredLocationNeedsUpdate(
                for: snapshot.event,
                locationText: updatedLocation
            )
            let needsTimeZoneUpdate = await footballTimeZoneNeedsUpdate(
                for: snapshot.event,
                locationText: updatedLocation
            )
            let needsAlertUpdate = footballAlertConfigurationNeedsUpdate(
                for: snapshot.event,
                desiredRelativeOffset: footballCalendarAlertRelativeOffset()
            )

            let needsUpdate = snapshot.event.title != updatedTitle
                || snapshot.event.location != updatedLocation
                || snapshot.event.startDate != updatedStartDate
                || snapshot.event.endDate != updatedEndDate
                || snapshot.event.url != nil
                || needsStructuredLocationUpdate
                || needsTimeZoneUpdate
                || needsAlertUpdate

            guard needsUpdate else { continue }

            snapshot.event.title = updatedTitle
            await applyFootballLocation(to: snapshot.event, locationText: updatedLocation)
            await applyFootballTimeZone(to: snapshot.event, locationText: updatedLocation)
            snapshot.event.startDate = updatedStartDate
            snapshot.event.endDate = updatedEndDate
            snapshot.event.url = nil
            applyFootballAlertConfiguration(to: snapshot.event)

            do {
                try eventStore.save(snapshot.event, span: .thisEvent, commit: false)
                if let refreshedRecord = managedFootballEventRecord(
                    for: snapshot.event,
                    reference: snapshot.reference
                ) {
                    refreshedRecordsByReference[snapshot.reference] = refreshedRecord
                }
                updatedReferences.append(snapshot.reference)
                hasPendingChanges = true
            } catch {
                continue
            }
        }

        if hasPendingChanges {
            try? eventStore.commit()
            refreshManagedFootballRecordsAfterPersistedAlertCleanup(
                &refreshedRecordsByReference,
                references: updatedReferences
            )
        }

        persistManagedFootballEventRecords(Array(refreshedRecordsByReference.values))
    }

    func applyFootballLocation(to event: EKEvent, locationText: String?) async {
        let normalizedLocationText = normalizedLocation(for: locationText)
        event.location = normalizedLocationText
        event.structuredLocation = await footballStructuredLocation(for: normalizedLocationText)
    }

    func footballStructuredLocationNeedsUpdate(for event: EKEvent, locationText: String?) async -> Bool {
        let normalizedLocationText = normalizedLocation(for: locationText)
        let currentStructuredTitle = normalizedLocation(for: event.structuredLocation?.title)

        switch normalizedLocationText {
        case nil:
            return event.structuredLocation != nil
        case let normalizedLocationText?:
            guard let structuredLocation = event.structuredLocation else {
                return true
            }

            guard currentStructuredTitle == normalizedLocationText else {
                return true
            }

            guard let currentGeoLocation = structuredLocation.geoLocation else {
                return true
            }

            guard let resolvedCoordinate = await LocationCoordinateResolver.shared.coordinate(for: normalizedLocationText) else {
                return true
            }

            let resolvedGeoLocation = CLLocation(
                latitude: resolvedCoordinate.latitude,
                longitude: resolvedCoordinate.longitude
            )

            return currentGeoLocation.distance(from: resolvedGeoLocation) > Self.footballStructuredLocationToleranceMeters
        }
    }

    func footballStructuredLocation(for locationText: String?) async -> EKStructuredLocation? {
        guard let locationText else { return nil }
        guard let coordinate = await LocationCoordinateResolver.shared.coordinate(for: locationText) else {
            return nil
        }

        let structuredLocation = EKStructuredLocation(title: locationText)
        structuredLocation.geoLocation = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        return structuredLocation
    }

    func approximateEndDate(for match: FootballFixtureMatch) -> Date {
        Self.approximateFootballMatchEndDate(for: match, now: fixedSecondNow())
    }

    nonisolated static func approximateFootballMatchEndDate(
        for match: FootballFixtureMatch,
        now: Date = AlertCalendarClock.nowRoundedToSecond()
    ) -> Date {
        let approximatedDuration = approximateFootballMatchDuration(for: match, now: now)
        let effectiveStartDate = footballEffectiveStartDate(for: match)
        let bufferedEstimatedEnd = effectiveStartDate.addingTimeInterval(
            approximatedDuration + footballEstimatedEndMarginDuration
        )

        switch match.statusState {
        case .finished:
            if let actualEndDate = match.actualEndDate,
               actualEndDate > effectiveStartDate {
                return actualEndDate
            }
            return bufferedEstimatedEnd
        case .inProgress:
            if let liveEstimatedEnd = footballEstimatedLiveMatchEndDate(
                for: match,
                now: now,
                fallbackEndDate: bufferedEstimatedEnd
            ) {
                return liveEstimatedEnd
            }
            let minimumLiveEnd = now.addingTimeInterval(footballLiveMinimumTailDuration)
            return footballRoundedLiveEndDate(max(bufferedEstimatedEnd, minimumLiveEnd), now: now)
        case .scheduled:
            return bufferedEstimatedEnd
        case .unknown:
            if effectiveStartDate <= now {
                if let liveEstimatedEnd = footballEstimatedLiveMatchEndDate(
                    for: match,
                    now: now,
                    fallbackEndDate: bufferedEstimatedEnd
                ) {
                    return liveEstimatedEnd
                }
                let minimumLiveEnd = now.addingTimeInterval(footballLiveMinimumTailDuration)
                return footballRoundedLiveEndDate(max(bufferedEstimatedEnd, minimumLiveEnd), now: now)
            }
            return bufferedEstimatedEnd
        }
    }

    nonisolated static func footballEstimatedLiveMatchEndDate(
        for match: FootballFixtureMatch,
        now: Date,
        fallbackEndDate: Date
    ) -> Date? {
        guard match.statusReliability == .reported else { return nil }

        let normalizedStatus = footballNormalizedStatusText(match.statusText)
        guard footballInterruptedStatusBadgeText(from: normalizedStatus) == nil else {
            return nil
        }

        let phase = footballLiveMatchPhase(for: match, now: now)
        let tailDuration = footballLiveTailDuration(for: match, phase: phase, now: now)
        let minimumEndDate = now.addingTimeInterval(tailDuration)

        guard let remainingDuration = footballEstimatedLiveRemainingDuration(
            for: match,
            phase: phase,
            now: now
        ) else {
            return footballRoundedLiveEndDate(max(fallbackEndDate, minimumEndDate), now: now)
        }

        return footballRoundedLiveEndDate(
            max(now.addingTimeInterval(remainingDuration), minimumEndDate),
            now: now
        )
    }

    nonisolated static func footballEstimatedLiveRemainingDuration(
        for match: FootballFixtureMatch,
        phase: FootballLiveMatchPhase,
        now: Date
    ) -> TimeInterval? {
        switch phase {
        case .firstHalf:
            let minute = min(max(footballLiveMinute(for: match, now: now) ?? 0, 0), 45)
            let firstHalfRemaining = TimeInterval(max(0, 45 - minute) * 60)
            return firstHalfRemaining
                + footballHalfTimeBreakDuration
                + TimeInterval(45 * 60)
                + footballEstimatedEndMarginDuration
                + footballPotentialExtraTimeReserveDuration(for: match, now: now)

        case .halfTime:
            let scheduledSecondHalfStart = footballEffectiveStartDate(for: match)
                .addingTimeInterval(TimeInterval(45 * 60) + footballHalfTimeBreakDuration)
            let halfTimeRemaining = max(0, scheduledSecondHalfStart.timeIntervalSince(now))
            return halfTimeRemaining
                + TimeInterval(45 * 60)
                + footballEstimatedEndMarginDuration
                + footballPotentialExtraTimeReserveDuration(for: match, now: now)

        case .secondHalf:
            let minute = min(max(footballLiveMinute(for: match, now: now) ?? 46, 46), 90)
            let regulationRemaining = TimeInterval(max(0, 90 - minute) * 60)
            return regulationRemaining
                + footballEstimatedEndMarginDuration
                + footballPotentialExtraTimeReserveDuration(for: match, now: now)

        case .extraTime:
            let minute = min(max(footballLiveMinute(for: match, now: now) ?? 91, 91), 120)
            let extraTimeRemaining = TimeInterval(max(0, 120 - minute) * 60)
            return extraTimeRemaining
                + footballEstimatedEndMarginDuration
                + footballPotentialPenaltyReserveDuration(for: match, minute: minute)

        case .penalties:
            return footballPenaltyShootoutEstimateDuration

        case .unknown:
            return nil
        }
    }

    nonisolated static func footballPotentialExtraTimeReserveDuration(
        for match: FootballFixtureMatch,
        now: Date
    ) -> TimeInterval {
        guard footballCanReachExtraTime(match) else { return 0 }
        guard footballExtraTimeStillLooksLikely(for: match, now: now) else { return 0 }
        return TimeInterval(30 * 60) + footballEstimatedEndMarginDuration
    }

    nonisolated static func footballPotentialPenaltyReserveDuration(
        for match: FootballFixtureMatch,
        minute: Int
    ) -> TimeInterval {
        guard footballCanReachExtraTime(match), footballScoresAreLevel(match) else { return 0 }
        return minute >= 116 ? footballPenaltyShootoutEstimateDuration : 0
    }

    nonisolated static func footballLiveTailDuration(
        for match: FootballFixtureMatch,
        phase: FootballLiveMatchPhase,
        now: Date
    ) -> TimeInterval {
        switch phase {
        case .penalties, .extraTime, .halfTime, .firstHalf:
            return footballLiveShortTailDuration
        case .secondHalf:
            let minute = footballLiveMinute(for: match, now: now) ?? 0
            return minute >= 88 ? footballLiveLateTailDuration : footballLiveShortTailDuration
        case .unknown:
            return footballLiveMinimumTailDuration
        }
    }

    nonisolated static func footballRoundedLiveEndDate(_ date: Date, now: Date) -> Date {
        let interval = footballLiveEndDateRoundingInterval
        guard interval > 0 else { return date }

        let roundedTime = ceil(date.timeIntervalSince1970 / interval) * interval
        let roundedDate = Date(timeIntervalSince1970: roundedTime)
        guard roundedDate > now else {
            return now.addingTimeInterval(footballLiveLateTailDuration)
        }
        return roundedDate
    }

    nonisolated static func approximateFootballMatchDuration(
        for match: FootballFixtureMatch,
        now: Date = AlertCalendarClock.nowRoundedToSecond()
    ) -> TimeInterval {
        let normalizedStatus = footballNormalizedStatusText(match.statusText)

        if let interruptionBadge = footballInterruptedStatusBadgeText(from: normalizedStatus) {
            return footballInterruptedMatchDuration(for: match, badgeText: interruptionBadge)
        }

        if footballStatusIndicatesPenaltyShootout(for: match, now: now) {
            return footballPenaltyMatchDuration
        }

        if footballStatusIndicatesExtraTime(for: match, now: now) {
            return footballExtraTimeMatchDuration
        }

        guard footballCanReachExtraTime(match) else {
            return footballRegulationMatchDuration
        }

        switch match.statusState {
        case .finished:
            return footballRegulationMatchDuration
        case .scheduled:
            return footballExtraTimeMatchDuration
        case .inProgress, .unknown:
            return footballExtraTimeStillLooksLikely(for: match, now: now)
                ? footballExtraTimeMatchDuration
                : footballRegulationMatchDuration
        }
    }

    nonisolated static func footballFixtureSortPriority(
        for match: FootballFixtureMatch,
        now: Date
    ) -> (Int, TimeInterval, String) {
        if match.statusState == .inProgress {
            return (0, match.startDate.timeIntervalSince1970, match.id)
        }

        if match.startDate >= now {
            return (1, match.startDate.timeIntervalSince1970, match.id)
        }

        return (2, -match.startDate.timeIntervalSince1970, match.id)
    }

    nonisolated static func resolvedFootballSectionMatches(
        _ matches: [FootballFixtureMatch],
        cachedMatchesByID: [String: FootballFixtureMatch],
        now: Date
    ) -> [FootballFixtureMatch] {
        matches
            .map { cachedMatchesByID[$0.id] ?? $0 }
            .filter { !FootballFixtureFormatter.hasUnknownParticipants(in: $0) }
            .map { match in
                (match: match, priority: footballFixtureSortPriority(for: match, now: now))
            }
            .sorted { $0.priority < $1.priority }
            .map(\.match)
    }

    func updateFootballCompetitionSection(
        _ competitionID: String,
        transform: (FootballMenuCompetitionSection) -> FootballMenuCompetitionSection
    ) {
        guard let index = footballMenuSections.firstIndex(where: { $0.id == competitionID }) else { return }
        let nextSection = transform(footballMenuSections[index])
        guard footballMenuSections[index] != nextSection else { return }
        footballMenuSections[index] = nextSection
    }

    func updateManagedFootballMatches(using trackedEvents: [ManagedFootballEventSnapshot], now: Date) {
        let snapshotsByMatchID = trackedEvents.reduce(into: [String: ManagedFootballEventSnapshot]()) { partialResult, snapshot in
            guard partialResult[snapshot.reference.matchID] == nil else { return }
            partialResult[snapshot.reference.matchID] = snapshot
        }

        let nextMatches = snapshotsByMatchID.values
            .compactMap { snapshot in
                footballMatchesByID[snapshot.reference.matchID]
            }
            .map { match in
                (match: match, priority: Self.footballFixtureSortPriority(for: match, now: now))
            }
            .sorted { $0.priority < $1.priority }
            .map(\.match)
        guard managedFootballMatches != nextMatches else { return }
        managedFootballMatches = nextMatches
    }

    nonisolated static func liveAndNextDayMatches(
        from matches: [FootballFixtureMatch],
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [FootballFixtureMatch] {
        let upperBound = calendar.date(byAdding: .hour, value: 24, to: now) ?? now.addingTimeInterval(24 * 60 * 60)

        let filteredMatches = matches
            .filter { match in
                guard !FootballFixtureFormatter.hasUnknownParticipants(in: match) else {
                    return false
                }
                if match.statusState == .inProgress {
                    return true
                }
                if match.statusReliability == .awaitingLiveData || match.statusReliability == .delayedLiveData {
                    return true
                }
                return match.startDate >= now && match.startDate <= upperBound
            }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate {
                    return lhs.startDate < rhs.startDate
                }
                return lhs.id < rhs.id
            }

        return deduplicatedFootballMatches(filteredMatches)
    }

    nonisolated static func upcomingManagedFootballMatches(
        from matches: [FootballFixtureMatch],
        now: Date
    ) -> [FootballFixtureMatch] {
        let filteredMatches = matches
            .filter { match in
                guard !FootballFixtureFormatter.hasUnknownParticipants(in: match) else {
                    return false
                }
                if match.statusState == .inProgress {
                    return true
                }
                if match.statusReliability == .awaitingLiveData || match.statusReliability == .delayedLiveData {
                    return true
                }
                return match.startDate > now
            }
            .sorted { lhs, rhs in
                let lhsPriority = lhs.statusState == .inProgress ? 0 : 1
                let rhsPriority = rhs.statusState == .inProgress ? 0 : 1
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                if lhs.startDate != rhs.startDate {
                    return lhs.startDate < rhs.startDate
                }
                return lhs.id < rhs.id
            }

        return deduplicatedFootballMatches(filteredMatches)
    }

    nonisolated static func shouldDisplayFinishedFootballMatch(
        _ match: FootballFixtureMatch,
        now: Date,
        lookbackDays: Int
    ) -> Bool {
        guard match.statusState == .finished else { return true }

        let normalizedLookbackDays = max(1, lookbackDays)
        let cutoffDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -normalizedLookbackDays, to: now)
            ?? now.addingTimeInterval(-Double(normalizedLookbackDays) * 24 * 60 * 60)
        return approximateFootballMatchEndDate(for: match, now: now) >= cutoffDate
    }

    nonisolated static func deduplicatedFootballMatches(_ matches: [FootballFixtureMatch]) -> [FootballFixtureMatch] {
        var seen = Set<String>()
        return matches.filter { seen.insert($0.id).inserted }
    }


}
