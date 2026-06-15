import AppKit
import CoreLocation
import EventKit
import Foundation

extension CalendarMonitor {
    func recoverManagedFootballEventRecordsIfNeeded(now: Date) async {
        let orphanEvents = unresolvedManagedFootballCandidateEvents(now: now)
        guard !orphanEvents.isEmpty else { return }

        var candidateMatches = Array(footballMatchesByID.values)
        let unresolvedEvents = orphanEvents.filter { matchedFootballFixture(for: $0, in: candidateMatches) == nil }

        if !unresolvedEvents.isEmpty {
            do {
                let fetchedMatches = try await footballClient.fetchMatches(for: FootballCompetitionPreset.menuPresets)
                let refreshedMatches = await footballClient.refreshStatusesIfNeeded(for: fetchedMatches)
                let resolvedMatches = matchesPreservingKnownTimingContext(refreshedMatches)
                await cacheFootballMatches(resolvedMatches)
                candidateMatches = Array(footballMatchesByID.values)
            } catch {
                return
            }
        }

        var recordsByReference = Dictionary(uniqueKeysWithValues: managedFootballEventRecords.map { ($0.reference, $0) })
        var didRecoverRecord = false
        var didRemoveDuplicateEvent = false
        let preferredCalendarID = resolvedFootballTargetCalendar()?.calendarIdentifier
        let matchedEventsByReference = orphanEvents.reduce(into: [ManagedFootballFixtureReference: [EKEvent]]()) { partialResult, event in
            guard let matchedFixture = matchedFootballFixture(for: event, in: candidateMatches) else { return }
            let reference = ManagedFootballFixtureReference(
                matchID: matchedFixture.id,
                competitionSlug: matchedFixture.competitionSlug
            )
            partialResult[reference, default: []].append(event)
        }

        for (reference, matchedEvents) in matchedEventsByReference {
            let sortedEvents = sortManagedFootballEvents(
                matchedEvents,
                preferredCalendarID: preferredCalendarID
            )
            guard let keeper = sortedEvents.first else { continue }

            if recordsByReference[reference] == nil,
               let recoveredRecord = managedFootballEventRecord(for: keeper, reference: reference) {
                recordsByReference[reference] = recoveredRecord
                didRecoverRecord = true
            }

            for duplicate in sortedEvents.dropFirst() {
                do {
                    try eventStore.remove(duplicate, span: .thisEvent, commit: false)
                    didRemoveDuplicateEvent = true
                } catch {
                    continue
                }
            }
        }

        guard didRecoverRecord || didRemoveDuplicateEvent else { return }
        if didRemoveDuplicateEvent {
            try? eventStore.commit()
        }
        persistManagedFootballEventRecords(Array(recordsByReference.values))
    }

    func unresolvedManagedFootballCandidateEvents(now: Date) -> [EKEvent] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -Self.footballTrackedLookbackDays, to: now) ?? now
        let end = calendar.date(byAdding: .day, value: Self.footballTrackedLookaheadDays, to: now) ?? now
        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: eventStore.calendars(for: .event)
        )

        return eventStore.events(matching: predicate).filter { event in
            guard managedFootballReference(for: event) == nil else { return false }
            guard let eventStartDate = event.startDate else { return false }
            guard Self.isManagedFootballEventWithinSuggestionWindow(startDate: eventStartDate, now: now) else { return false }
            return FootballFixtureFormatter.looksLikeFootballCalendarTitle(normalizedTitle(event.title))
        }
    }

    func matchedFootballFixture(
        for event: EKEvent,
        in matches: [FootballFixtureMatch]
    ) -> FootballFixtureMatch? {
        guard let eventStartDate = event.startDate else { return nil }

        let eventTitle = normalizedTitle(event.title)
        let eventIdentityKey = FootballFixtureFormatter.calendarIdentityKey(fromCalendarTitle: eventTitle)
        let nearbyMatches = matches.filter { match in
            abs(Self.footballEffectiveStartDate(for: match).timeIntervalSince(eventStartDate)) <= Self.footballManagedEventMatchingTolerance
        }

        let exactTitleMatches = nearbyMatches.filter { match in
            normalizedTitle(FootballFixtureFormatter.calendarTitle(for: match)) == eventTitle
        }
        if exactTitleMatches.count == 1 {
            return exactTitleMatches[0]
        }

        if let eventIdentityKey {
            let identityMatches = nearbyMatches.filter { match in
                FootballFixtureFormatter.calendarIdentityKey(for: match) == eventIdentityKey
            }
            if identityMatches.count == 1 {
                return identityMatches[0]
            }
        }

        return nil
    }

    func footballMenuBarDisplay(for match: FootballFixtureMatch) -> FootballMenuBarDisplay {
        let competitionLogoURL = footballLocalLogoPathsByCompetitionSlug[match.competitionSlug].map(URL.init(fileURLWithPath:))
        let homeLogoURL = footballLocalLogoPathsByTeamID[match.homeTeam.id].map(URL.init(fileURLWithPath:))
        let awayLogoURL = footballLocalLogoPathsByTeamID[match.awayTeam.id].map(URL.init(fileURLWithPath:))
        return FootballFixtureFormatter.menuBarDisplay(
            for: match,
            competitionLocalLogoURL: competitionLogoURL,
            homeLocalLogoURL: homeLogoURL,
            awayLocalLogoURL: awayLogoURL
        )
    }


}
