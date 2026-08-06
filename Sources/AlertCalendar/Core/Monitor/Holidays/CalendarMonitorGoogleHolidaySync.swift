import EventKit
import Foundation

extension CalendarMonitor {
    nonisolated static let currentGoogleHolidayIdentityVersion = 3
    nonisolated static let googleHolidayManagedMarker = "Managed by Alert Calendar • Google Holidays v3"
    nonisolated static let legacyGoogleHolidayManagedMarkers = [
        "Managed by Alert Calendar • Google Holidays v1",
        "Managed by Alert Calendar • Google Holidays v2",
    ]

    func refreshGoogleHolidays(forceRefresh: Bool = false) async {
        guard !isSyncingGoogleHolidays else { return }

        let settings = snapshotSettings()
        let countryIDs = GoogleHolidayCountry.normalizedCountryIDs(settings.googleHolidayCountryIDs)

        guard hasEventsAccess else {
            googleHolidaySyncErrorDescription = nil
            return
        }

        guard !countryIDs.isEmpty else {
            googleHolidaySyncErrorDescription = nil
            if forceRefresh || !managedGoogleHolidayEventRecords.isEmpty {
                isSyncingGoogleHolidays = true
                await removeAllManagedGoogleHolidayEvents()
                isSyncingGoogleHolidays = false
                defaults.set(
                    Self.currentGoogleHolidayIdentityVersion,
                    forKey: DefaultsKeys.googleHolidayIdentityVersion
                )
            }
            return
        }

        guard let targetCalendar = resolvedGoogleHolidayTargetCalendar(settings: settings) else {
            googleHolidaySyncErrorDescription = nil
            return
        }

        let now = fixedSecondNow()
        let calendar = holidayCalendar()
        let requiresIdentityMigration =
            defaults.integer(forKey: DefaultsKeys.googleHolidayIdentityVersion)
                < Self.currentGoogleHolidayIdentityVersion
            || managedGoogleHolidayEventRecords.contains { record in
                record.holiday.id != GoogleHolidayMerger.semanticKey(
                    title: record.holiday.title,
                    startDate: record.holiday.startDate,
                    calendar: calendar
                )
        }
        guard shouldRefreshGoogleHolidays(
            now: now,
            forceRefresh: forceRefresh || requiresIdentityMigration
        ) else {
            return
        }

        isSyncingGoogleHolidays = true
        defer { isSyncingGoogleHolidays = false }
        lastGoogleHolidayRefreshAttemptDate = now
        googleHolidaySyncErrorDescription = nil

        do {
            let fetched = try await googleHolidayClient.fetchHolidays(
                countryIDs: countryIDs,
                now: now,
                forceRefresh: true
            )
            let inWindow = fetched.filter { googleHolidaySyncWindowContains($0, now: now) }
            let merged = GoogleHolidayMerger.merge(inWindow, calendar: calendar)
            try await reconcileGoogleHolidayEvents(
                merged,
                targetCalendar: targetCalendar
            )
            ensureGoogleHolidayTargetCalendarIsSelected(targetCalendar.calendarIdentifier)
            markGoogleHolidaysRefreshed(at: now)
            defaults.set(now, forKey: DefaultsKeys.googleHolidayLastRefreshDate)
            defaults.set(
                Self.currentGoogleHolidayIdentityVersion,
                forKey: DefaultsKeys.googleHolidayIdentityVersion
            )
        } catch {
            googleHolidaySyncErrorDescription = error.localizedDescription
        }
    }

    private func shouldRefreshGoogleHolidays(
        now: Date,
        forceRefresh: Bool
    ) -> Bool {
        GoogleHolidayRefreshPolicy.isDue(
            lastRefreshDate: googleHolidayLastRefreshDate,
            lastAttemptDate: lastGoogleHolidayRefreshAttemptDate,
            now: now,
            forceRefresh: forceRefresh
        )
    }

    func persistManagedGoogleHolidayEventRecords(_ records: [ManagedGoogleHolidayEventRecord]) {
        var byHolidayID: [String: ManagedGoogleHolidayEventRecord] = [:]
        for record in records {
            let existing = byHolidayID[record.holiday.id]
            let candidateHasIdentifier = record.eventIdentifier != nil || record.eventUID != nil
            let existingHasIdentifier = existing?.eventIdentifier != nil || existing?.eventUID != nil
            if existing == nil || candidateHasIdentifier || !existingHasIdentifier {
                byHolidayID[record.holiday.id] = record
            }
        }

        let normalized = byHolidayID.values.sorted { lhs, rhs in
            if lhs.holiday.startDate != rhs.holiday.startDate {
                return lhs.holiday.startDate < rhs.holiday.startDate
            }
            return lhs.holiday.id < rhs.holiday.id
        }
        guard normalized != managedGoogleHolidayEventRecords else { return }
        managedGoogleHolidayEventRecords = normalized

        if normalized.isEmpty {
            defaults.removeObject(forKey: DefaultsKeys.managedGoogleHolidayEventRecords)
        } else if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: DefaultsKeys.managedGoogleHolidayEventRecords)
        }
    }

    private func reconcileGoogleHolidayEvents(
        _ desiredHolidays: [GoogleHolidayEvent],
        targetCalendar: EKCalendar
    ) async throws {
        let calendar = holidayCalendar()
        var existingByHolidayID: [String: [ExistingGoogleHolidayEvent]] = [:]
        let recordsByHolidayID = Dictionary(
            managedGoogleHolidayEventRecords.map { ($0.holiday.id, $0.holiday) },
            uniquingKeysWith: { existing, _ in existing }
        )
        var seenEventIdentities: Set<String> = []
        let existingEvents = await managedGoogleHolidayEvents(
            records: managedGoogleHolidayEventRecords,
            including: [targetCalendar]
        )
        for event in existingEvents {
            guard let holidayID = managedGoogleHolidayID(from: event.notes) else { continue }
            let identity = event.eventIdentifier ?? normalizedEventUID(for: event) ?? UUID().uuidString
            guard seenEventIdentities.insert(identity).inserted else { continue }
            existingByHolidayID[holidayID, default: []].append(
                ExistingGoogleHolidayEvent(
                    event: event,
                    recordedHoliday: recordsByHolidayID[holidayID]
                )
            )
        }

        var retained: [(holiday: GoogleHolidayEvent, event: EKEvent)] = []
        var pendingMutationCount = 0

        for holiday in desiredHolidays {
            var candidates = existingByHolidayID.removeValue(forKey: holiday.id) ?? []
            let migrationKeys = existingByHolidayID.compactMap { key, existingEvents -> String? in
                existingEvents.contains {
                    googleHolidayMigrationCandidate(
                        $0,
                        matches: holiday,
                        calendar: calendar
                    )
                } ? key : nil
            }
            for migrationKey in migrationKeys {
                candidates.append(contentsOf: existingByHolidayID.removeValue(forKey: migrationKey) ?? [])
            }

            let event: EKEvent
            if let preferred = candidates.first(where: {
                $0.event.calendar?.calendarIdentifier == targetCalendar.calendarIdentifier
            }) ?? candidates.first {
                event = preferred.event
                if googleHolidayEventNeedsUpdate(event, holiday: holiday, calendar: targetCalendar) {
                    applyGoogleHoliday(holiday, to: event, calendar: targetCalendar)
                    try eventStore.save(event, span: .thisEvent, commit: false)
                    pendingMutationCount += 1
                    pendingMutationCount = try await commitGoogleHolidayBatchIfNeeded(
                        pendingMutationCount
                    )
                }

                for duplicate in candidates where duplicate.event !== event {
                    try eventStore.remove(duplicate.event, span: .thisEvent, commit: false)
                    pendingMutationCount += 1
                    pendingMutationCount = try await commitGoogleHolidayBatchIfNeeded(
                        pendingMutationCount
                    )
                }
            } else {
                event = EKEvent(eventStore: eventStore)
                applyGoogleHoliday(holiday, to: event, calendar: targetCalendar)
                try eventStore.save(event, span: .thisEvent, commit: false)
                pendingMutationCount += 1
                pendingMutationCount = try await commitGoogleHolidayBatchIfNeeded(
                    pendingMutationCount
                )
            }
            retained.append((holiday, event))
        }

        for staleEvents in existingByHolidayID.values {
            for stale in staleEvents {
                try eventStore.remove(stale.event, span: .thisEvent, commit: false)
                pendingMutationCount += 1
                pendingMutationCount = try await commitGoogleHolidayBatchIfNeeded(
                    pendingMutationCount
                )
            }
        }

        _ = try await commitGoogleHolidayBatchIfNeeded(pendingMutationCount, force: true)

        let nextRecords = retained.compactMap { holiday, event -> ManagedGoogleHolidayEventRecord? in
            guard let calendarIdentifier = event.calendar?.calendarIdentifier else { return nil }
            return ManagedGoogleHolidayEventRecord(
                holiday: holiday,
                calendarIdentifier: calendarIdentifier,
                eventIdentifier: event.eventIdentifier,
                eventUID: normalizedEventUID(for: event)
            )
        }
        persistManagedGoogleHolidayEventRecords(nextRecords)
    }

    private func removeAllManagedGoogleHolidayEvents() async {
        var removedEventIdentities: Set<String> = []
        var pendingMutationCount = 0

        do {
            let targetCalendars = resolvedGoogleHolidayTargetCalendar().map { [$0] } ?? []
            let events = await managedGoogleHolidayEvents(
                records: managedGoogleHolidayEventRecords,
                including: targetCalendars
            )
            for event in events {
                let identity = event.eventIdentifier ?? normalizedEventUID(for: event) ?? UUID().uuidString
                guard removedEventIdentities.insert(identity).inserted else { continue }
                try eventStore.remove(event, span: .thisEvent, commit: false)
                pendingMutationCount += 1
                pendingMutationCount = try await commitGoogleHolidayBatchIfNeeded(
                    pendingMutationCount
                )
            }
            _ = try await commitGoogleHolidayBatchIfNeeded(pendingMutationCount, force: true)
            persistManagedGoogleHolidayEventRecords([])
        } catch {
            googleHolidaySyncErrorDescription = "Some managed holiday events could not be removed."
        }
    }

    private func managedGoogleHolidayEvents(
        records: [ManagedGoogleHolidayEventRecord],
        including additionalCalendars: [EKCalendar]
    ) async -> [EKEvent] {
        let recordCalendarIDs = Set(records.map(\.calendarIdentifier))
        var calendarsByID = Dictionary(
            uniqueKeysWithValues: eventStore.calendars(for: .event)
                .filter { recordCalendarIDs.contains($0.calendarIdentifier) }
                .map { ($0.calendarIdentifier, $0) }
        )
        for calendar in additionalCalendars {
            calendarsByID[calendar.calendarIdentifier] = calendar
        }
        let calendars = Array(calendarsByID.values)
        guard !calendars.isEmpty else { return [] }

        let calendar = holidayCalendar()
        let now = fixedSecondNow()
        let year = calendar.component(.year, from: now)
        let defaultStart = calendar.date(from: DateComponents(year: year - 1, month: 1, day: 1))
            ?? now.addingTimeInterval(-366 * 86_400)
        let defaultEnd = calendar.date(from: DateComponents(year: year + 6, month: 1, day: 1))
            ?? now.addingTimeInterval(6 * 366 * 86_400)
        let earliestRecordDate = records.map(\.holiday.startDate).min() ?? defaultStart
        let latestRecordDate = records.map(\.holiday.endDateExclusive).max() ?? defaultEnd
        let searchStart = min(defaultStart, earliestRecordDate.addingTimeInterval(-86_400))
        let searchEnd = max(defaultEnd, latestRecordDate.addingTimeInterval(2 * 86_400))
        let predicates = googleHolidayEventSearchPredicates(
            start: searchStart,
            end: searchEnd,
            calendars: calendars,
            calendar: calendar
        )
        let request = GoogleHolidayEventSearchRequest(
            eventStore: eventStore,
            predicates: predicates
        )
        let result = await Task.detached(priority: .userInitiated) {
            request.execute()
        }.value
        return result.events.filter { event in
            managedGoogleHolidayID(from: event.notes) != nil
        }
    }

    private func googleHolidayEventSearchPredicates(
        start: Date,
        end: Date,
        calendars: [EKCalendar],
        calendar: Calendar
    ) -> [NSPredicate] {
        var predicates: [NSPredicate] = []
        var intervalStart = start
        while intervalStart < end {
            let proposedEnd = calendar.date(byAdding: .year, value: 3, to: intervalStart) ?? end
            let intervalEnd = min(proposedEnd, end)
            predicates.append(
                eventStore.predicateForEvents(
                    withStart: intervalStart,
                    end: intervalEnd,
                    calendars: calendars
                )
            )
            intervalStart = intervalEnd
        }
        return predicates
    }

    private func commitGoogleHolidayBatchIfNeeded(
        _ pendingMutationCount: Int,
        force: Bool = false
    ) async throws -> Int {
        let batchSize = 100
        guard pendingMutationCount >= batchSize || (force && pendingMutationCount > 0) else {
            return pendingMutationCount
        }
        try eventStore.commit()
        await Task.yield()
        return 0
    }

    private func applyGoogleHoliday(
        _ holiday: GoogleHolidayEvent,
        to event: EKEvent,
        calendar: EKCalendar
    ) {
        event.calendar = calendar
        event.title = holiday.calendarTitle
        event.isAllDay = true
        event.startDate = holiday.startDate
        event.endDate = Self.googleHolidayCalendarEndDate(
            endDateExclusive: holiday.endDateExclusive
        )
        event.availability = .free
        event.url = holiday.sourceURL
        event.notes = googleHolidayNotes(for: holiday)
        event.alarms = []
    }

    private func googleHolidayEventNeedsUpdate(
        _ event: EKEvent,
        holiday: GoogleHolidayEvent,
        calendar: EKCalendar
    ) -> Bool {
        let gregorian = holidayCalendar()
        let eventEndDateExclusive = Self.googleHolidayExclusiveEndDate(
            fromCalendarEndDate: event.endDate,
            calendar: gregorian
        )
        return event.calendar?.calendarIdentifier != calendar.calendarIdentifier
            || event.title != holiday.calendarTitle
            || !gregorian.isDate(event.startDate, inSameDayAs: holiday.startDate)
            || !gregorian.isDate(eventEndDateExclusive, inSameDayAs: holiday.endDateExclusive)
            || !event.isAllDay
            || event.availability != .free
            || event.url != holiday.sourceURL
            || event.notes != googleHolidayNotes(for: holiday)
            || !(event.alarms ?? []).isEmpty
    }

    private func googleHolidayNotes(for holiday: GoogleHolidayEvent) -> String {
        [
            Self.googleHolidayManagedMarker,
            "Countries: \(holiday.countryNames.joined(separator: ", "))",
            "Holiday key: \(holiday.id)",
            "Source: Google Calendar public holiday feeds",
        ].joined(separator: "\n")
    }

    private func managedGoogleHolidayID(from notes: String?) -> String? {
        guard Self.isManagedGoogleHolidayNotes(notes) else { return nil }
        return notes?
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("Holiday key: ") })
            .map { String($0.dropFirst("Holiday key: ".count)) }
    }

    nonisolated static func googleHolidayCalendarEndDate(
        endDateExclusive: Date
    ) -> Date {
        endDateExclusive.addingTimeInterval(-1)
    }

    nonisolated static func googleHolidayExclusiveEndDate(
        fromCalendarEndDate rawEndDate: Date,
        calendar: Calendar = .current
    ) -> Date {
        let endDay = calendar.startOfDay(for: rawEndDate)
        if abs(rawEndDate.timeIntervalSince(endDay)) < 1 {
            return endDay
        }
        return calendar.date(byAdding: .day, value: 1, to: endDay)
            ?? endDay.addingTimeInterval(86_400)
    }

    nonisolated static func isManagedGoogleHolidayNotes(_ notes: String?) -> Bool {
        guard let notes else { return false }
        return notes.contains(googleHolidayManagedMarker)
            || legacyGoogleHolidayManagedMarkers.contains(where: notes.contains)
    }

    private func googleHolidaySyncWindowContains(
        _ event: GoogleHolidaySourceEvent,
        now: Date
    ) -> Bool {
        let calendar = holidayCalendar()
        let year = calendar.component(.year, from: now)
        let start = calendar.date(from: DateComponents(year: year - 1, month: 1, day: 1))
            ?? now.addingTimeInterval(-366 * 86_400)
        let end = calendar.date(from: DateComponents(year: year + 6, month: 1, day: 1))
            ?? now.addingTimeInterval(6 * 366 * 86_400)
        return event.endDateExclusive > start && event.startDate < end
    }

    private func holidayCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

}

private struct GoogleHolidayEventSearchRequest: @unchecked Sendable {
    let eventStore: EKEventStore
    let predicates: [NSPredicate]

    func execute() -> GoogleHolidayEventSearchResult {
        var eventsByIdentity: [String: EKEvent] = [:]
        for predicate in predicates {
            for event in eventStore.events(matching: predicate) {
                let identity = event.eventIdentifier
                    ?? event.calendarItemExternalIdentifier
                    ?? "\(event.calendar?.calendarIdentifier ?? "")|\(event.startDate.timeIntervalSinceReferenceDate)|\(event.title ?? "")"
                eventsByIdentity[identity] = event
            }
        }
        return GoogleHolidayEventSearchResult(events: Array(eventsByIdentity.values))
    }
}

private struct GoogleHolidayEventSearchResult: @unchecked Sendable {
    let events: [EKEvent]
}
