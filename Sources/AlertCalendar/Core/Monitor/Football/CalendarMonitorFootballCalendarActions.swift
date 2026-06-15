import AppKit
import CoreLocation
import EventKit
import Foundation

extension CalendarMonitor {
    func addFootballMatchToCalendar(_ match: FootballFixtureMatch) async {
        guard hasEventsAccess else {
            calendarAccessDescription = "Calendar access is required to add fixtures."
            return
        }

        guard let calendar = resolvedFootballTargetCalendar() else {
            calendarAccessDescription = "Choose a writable event calendar before adding fixtures."
            return
        }

        let match = await resolvedFootballMatchForCalendarAdd(match)
        let reference = ManagedFootballFixtureReference(
            matchID: match.id,
            competitionSlug: match.competitionSlug
        )
        let now = fixedSecondNow()
        if trackedFootballEvents(now: now).contains(where: { $0.reference == reference }) {
            await cacheFootballMatches([match])
            managedFootballMatchIDs.insert(match.id)
            updateManagedFootballMatches(using: trackedFootballEvents(now: now), now: now)
            refreshNow(reason: .footballCalendarAction)
            return
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = FootballFixtureFormatter.calendarTitle(for: match)
        await applyFootballLocation(to: event, locationText: match.locationText)
        await applyFootballTimeZone(to: event, locationText: match.locationText)
        event.startDate = Self.footballEffectiveStartDate(for: match)
        event.endDate = approximateEndDate(for: match)
        applyFootballAlertConfiguration(to: event)

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            let persistedEvent = persistCleanFootballAlertConfigurationIfNeeded(for: event.eventIdentifier) ?? event
            await cacheFootballMatches([match])
            ensureFootballTargetCalendarIsSelected(calendar.calendarIdentifier)
            upsertManagedFootballEventRecord(for: persistedEvent, reference: reference)
            managedFootballMatchIDs.insert(match.id)
            updateManagedFootballMatches(using: trackedFootballEvents(now: now), now: now)
            refreshNow(reason: .footballCalendarAction)
        } catch {
            calendarAccessDescription = "Could not save the selected fixture."
        }
    }

    func resolvedFootballMatchForCalendarAdd(_ match: FootballFixtureMatch) async -> FootballFixtureMatch {
        let previousMatch = footballMatchesByID[match.id]
        let baseMatch = Self.footballMatchPreservingKnownTimingContext(match, previousMatch: previousMatch)
        let now = fixedSecondNow()
        let shouldForceSummary = baseMatch.statusState == .finished
            || baseMatch.statusState == .inProgress
            || (baseMatch.statusState == .unknown && baseMatch.startDate <= now)

        guard shouldForceSummary else { return baseMatch }

        let refreshedMatch = await footballClient.refreshStatusesIfNeeded(
            for: [baseMatch],
            forceSummaryForMatchIDs: [baseMatch.id]
        ).first ?? baseMatch

        return Self.footballMatchPreservingKnownTimingContext(
            refreshedMatch,
            previousMatch: previousMatch
        )
    }

    func openFootballMatchInCalendar(_ match: FootballFixtureMatch) {
        let reference = ManagedFootballFixtureReference(
            matchID: match.id,
            competitionSlug: match.competitionSlug
        )

        let now = fixedSecondNow()
        guard let snapshot = trackedFootballEvents(now: now).first(where: { $0.reference == reference }) else {
            calendarAccessDescription = "Could not find the selected fixture in Calendar."
            _ = openCalendarApplication()
            return
        }

        Task { @MainActor in
            _ = openCalendarApplication()

            if revealCalendarEvent(snapshot.event) {
                return
            }

            try? await Task.sleep(nanoseconds: 350_000_000)
            if revealCalendarEvent(snapshot.event) {
                return
            }

            try? await Task.sleep(nanoseconds: 850_000_000)
            if revealCalendarEvent(snapshot.event) {
                return
            }

            calendarAccessDescription = "Could not reveal the event directly in Calendar."
            _ = openCalendarApplication()
        }
    }

    func removeFootballMatchFromCalendar(_ match: FootballFixtureMatch) {
        guard hasEventsAccess else {
            calendarAccessDescription = "Calendar access is required to remove fixtures."
            return
        }

        let reference = ManagedFootballFixtureReference(
            matchID: match.id,
            competitionSlug: match.competitionSlug
        )
        let now = fixedSecondNow()
        let trackedSnapshots = trackedFootballEvents(now: now).filter { $0.reference == reference }

        guard !trackedSnapshots.isEmpty else {
            removeManagedFootballEventRecord(for: reference)
            managedFootballMatchIDs.remove(match.id)
            updateManagedFootballMatches(using: trackedFootballEvents(now: now), now: now)
            refreshNow(reason: .footballCalendarAction)
            return
        }

        var removedAny = false
        for snapshot in trackedSnapshots {
            do {
                try eventStore.remove(snapshot.event, span: .thisEvent, commit: false)
                removedAny = true
            } catch {
                continue
            }
        }

        guard removedAny else {
            calendarAccessDescription = "Could not remove the selected fixture."
            return
        }

        do {
            try eventStore.commit()
            removeManagedFootballEventRecord(for: reference)
            managedFootballMatchIDs.remove(match.id)
            updateManagedFootballMatches(using: trackedFootballEvents(now: now), now: now)
            refreshNow(reason: .footballCalendarAction)
        } catch {
            calendarAccessDescription = "Could not remove the selected fixture."
        }
    }

    func writableFootballTargetCalendars() -> [AvailableCalendar] {
        footballTargetCalendars().map {
                AvailableCalendar(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    color: color(from: $0),
                    kind: .event,
                    accountTitle: normalizedAccountTitle(for: $0),
                    isSubscribed: $0.type == .subscription
                )
            }
    }

    func footballTargetCalendarID() -> String? {
        resolvedFootballTargetCalendar()?.calendarIdentifier
    }

    func isFootballMatchTracked(_ match: FootballFixtureMatch) -> Bool {
        managedFootballMatchIDs.contains(match.id)
    }

    func refreshManagedFootballTrackingSnapshot(now: Date) {
        guard hasEventsAccess else {
            if !managedFootballMatchIDs.isEmpty {
                managedFootballMatchIDs = []
            }
            if !managedFootballMatches.isEmpty {
                managedFootballMatches = []
            }
            return
        }
        _ = trackedFootballSnapshotsByRefreshingState(now: now)
    }

    func trackedFootballSnapshotsByRefreshingState(now: Date) -> [ManagedFootballEventSnapshot] {
        _ = removeDuplicateManagedFootballEvents()
        let trackedEvents = trackedFootballEvents(now: now)
        let trackedMatchIDs = Set(trackedEvents.map(\.reference.matchID))
        if trackedMatchIDs != managedFootballMatchIDs {
            managedFootballMatchIDs = trackedMatchIDs
        }
        updateManagedFootballMatches(using: trackedEvents, now: now)
        return trackedEvents
    }

    func footballCalendarAlertOption() -> FootballCalendarAlertOption {
        FootballCalendarAlertOption(rawValue: defaults.string(forKey: DefaultsKeys.footballCalendarAlertOption) ?? "")
            ?? .none
    }

    func footballCalendarAlertRelativeOffset() -> TimeInterval? {
        footballCalendarAlertOption().relativeOffset()
    }

    func footballTravelTime(for event: EKEvent) -> TimeInterval {
        EventTravelTimeResolver.travelTime(for: event)
    }

    func resetFootballTravelTime(on event: EKEvent) {
        EventTravelTimeResolver.resetTravelTime(on: event)
    }

    func footballAlertConfigurationNeedsUpdate(
        for event: EKEvent,
        desiredRelativeOffset: TimeInterval?
    ) -> Bool {
        let alarms = event.alarms ?? []

        guard let desiredRelativeOffset else {
            return !alarms.isEmpty
        }

        guard alarms.count == 1, let alarm = alarms.first else {
            return true
        }

        if alarm.absoluteDate != nil {
            return true
        }

        if abs(alarm.relativeOffset - desiredRelativeOffset) > 1 {
            return true
        }

        return footballTravelTime(for: event) > 0
    }

    func applyFootballAlertConfiguration(to event: EKEvent) {
        let desiredRelativeOffset = footballCalendarAlertRelativeOffset()

        guard footballAlertConfigurationNeedsUpdate(for: event, desiredRelativeOffset: desiredRelativeOffset) else {
            return
        }

        resetFootballTravelTime(on: event)
        if let desiredRelativeOffset {
            event.alarms = [EKAlarm(relativeOffset: desiredRelativeOffset)]
        } else {
            event.alarms = nil
        }
    }

    @discardableResult
    func persistCleanFootballAlertConfigurationIfNeeded(for eventIdentifier: String?) -> EKEvent? {
        guard let eventIdentifier else { return nil }

        let desiredRelativeOffset = footballCalendarAlertRelativeOffset()
        var latestEvent = eventStore.event(withIdentifier: eventIdentifier)

        for _ in 0 ..< 2 {
            guard let event = latestEvent else { return nil }
            guard footballAlertConfigurationNeedsUpdate(for: event, desiredRelativeOffset: desiredRelativeOffset) else {
                return event
            }

            resetFootballTravelTime(on: event)
            if let desiredRelativeOffset {
                event.alarms = [EKAlarm(relativeOffset: desiredRelativeOffset)]
            } else {
                event.alarms = nil
            }

            do {
                try eventStore.save(event, span: .thisEvent, commit: true)
            } catch {
                return event
            }

            latestEvent = eventStore.event(withIdentifier: eventIdentifier) ?? event
        }

        return latestEvent
    }

    func refreshManagedFootballRecordsAfterPersistedAlertCleanup(
        _ recordsByReference: inout [ManagedFootballFixtureReference: ManagedFootballEventRecord],
        references: [ManagedFootballFixtureReference]
    ) {
        for reference in references {
            guard let existingRecord = recordsByReference[reference] else { continue }
            guard let cleanedEvent = persistCleanFootballAlertConfigurationIfNeeded(for: existingRecord.eventIdentifier) else {
                continue
            }

            guard let refreshedRecord = managedFootballEventRecord(
                for: cleanedEvent,
                reference: reference
            ) else { continue }
            recordsByReference[reference] = refreshedRecord
        }
    }

    func applyManagedFootballAlertConfigurationIfNeeded(to trackedEvents: [ManagedFootballEventSnapshot]) {
        let desiredRelativeOffset = footballCalendarAlertRelativeOffset()
        var hasPendingChanges = false
        var refreshedRecordsByReference = Dictionary(uniqueKeysWithValues: managedFootballEventRecords.map { ($0.reference, $0) })
        var updatedReferences: [ManagedFootballFixtureReference] = []

        for snapshot in trackedEvents {
            guard footballAlertConfigurationNeedsUpdate(for: snapshot.event, desiredRelativeOffset: desiredRelativeOffset) else {
                continue
            }

            resetFootballTravelTime(on: snapshot.event)
            if let desiredRelativeOffset {
                snapshot.event.alarms = [EKAlarm(relativeOffset: desiredRelativeOffset)]
            } else {
                snapshot.event.alarms = nil
            }

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
            persistManagedFootballEventRecords(Array(refreshedRecordsByReference.values))
        }
    }


}
