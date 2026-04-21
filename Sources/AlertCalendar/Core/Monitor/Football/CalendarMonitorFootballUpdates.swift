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
                || needsAlertUpdate

            guard needsUpdate else { continue }

            snapshot.event.title = updatedTitle
            await applyFootballLocation(to: snapshot.event, locationText: updatedLocation)
            snapshot.event.startDate = updatedStartDate
            snapshot.event.endDate = updatedEndDate
            snapshot.event.url = nil
            applyFootballAlertConfiguration(to: snapshot.event)

            do {
                try eventStore.save(snapshot.event, span: .thisEvent, commit: false)
                refreshedRecordsByReference[snapshot.reference] = managedFootballEventRecord(
                    for: snapshot.event,
                    reference: snapshot.reference
                )
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
                return false
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

        let structuredLocation = EKStructuredLocation(title: locationText)
        if let coordinate = await LocationCoordinateResolver.shared.coordinate(for: locationText) {
            structuredLocation.geoLocation = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }

        return structuredLocation
    }

    func approximateEndDate(for match: FootballFixtureMatch) -> Date {
        Self.approximateFootballMatchEndDate(for: match, now: Date())
    }

    nonisolated static func approximateFootballMatchEndDate(
        for match: FootballFixtureMatch,
        now: Date = Date()
    ) -> Date {
        let approximatedDuration = approximateFootballMatchDuration(for: match, now: now)
        let effectiveStartDate = footballEffectiveStartDate(for: match)
        let bufferedEstimatedEnd = effectiveStartDate.addingTimeInterval(
            approximatedDuration + footballEstimatedEndMarginDuration
        )

        switch match.statusState {
        case .finished:
            return bufferedEstimatedEnd
        case .inProgress:
            let minimumLiveEnd = now.addingTimeInterval(footballLiveMinimumTailDuration)
            return max(bufferedEstimatedEnd, minimumLiveEnd)
        case .scheduled:
            return bufferedEstimatedEnd
        case .unknown:
            if effectiveStartDate <= now {
                let minimumLiveEnd = now.addingTimeInterval(footballLiveMinimumTailDuration)
                return max(bufferedEstimatedEnd, minimumLiveEnd)
            }
            return bufferedEstimatedEnd
        }
    }

    nonisolated static func approximateFootballMatchDuration(
        for match: FootballFixtureMatch,
        now: Date = Date()
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
            .sorted { lhs, rhs in
                footballFixtureSortPriority(for: lhs, now: now) < footballFixtureSortPriority(for: rhs, now: now)
            }
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
            .sorted { lhs, rhs in
                Self.footballFixtureSortPriority(for: lhs, now: now) < Self.footballFixtureSortPriority(for: rhs, now: now)
            }
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
