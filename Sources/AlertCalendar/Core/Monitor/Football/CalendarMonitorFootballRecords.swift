import AppKit
import CoreLocation
import EventKit
import Foundation

extension CalendarMonitor {
    func migrateLegacyManagedFootballEventsIfNeeded(now: Date) {
        let legacySnapshots = legacyManagedFootballEventSnapshots(
            now: now,
            lookbackDays: Self.footballManagedCleanupSearchLookbackDays,
            lookaheadDays: Self.footballManagedCleanupSearchLookaheadDays
        )
        guard !legacySnapshots.isEmpty else { return }

        let preferredCalendarID = resolvedFootballTargetCalendar()?.calendarIdentifier
        let groupedSnapshots = Dictionary(grouping: legacySnapshots, by: \.reference)
        var recordsByReference = Dictionary(uniqueKeysWithValues: managedFootballEventRecords.map { ($0.reference, $0) })
        var needsCommit = false

        for (reference, snapshots) in groupedSnapshots {
            let sortedSnapshots = sortManagedFootballSnapshots(snapshots, preferredCalendarID: preferredCalendarID)
            guard let keeper = sortedSnapshots.first else { continue }

            if keeper.event.url != nil {
                keeper.event.url = nil
                do {
                    try eventStore.save(keeper.event, span: .thisEvent, commit: false)
                    needsCommit = true
                } catch {
                    continue
                }
            }

            recordsByReference[reference] = managedFootballEventRecord(for: keeper.event, reference: reference)

            for duplicate in sortedSnapshots.dropFirst() {
                do {
                    try eventStore.remove(duplicate.event, span: .thisEvent, commit: false)
                    needsCommit = true
                } catch {
                    continue
                }
            }
        }

        if needsCommit {
            try? eventStore.commit()
        }

        persistManagedFootballEventRecords(Array(recordsByReference.values))
    }

    func sortManagedFootballSnapshots(
        _ snapshots: [ManagedFootballEventSnapshot],
        preferredCalendarID: String?
    ) -> [ManagedFootballEventSnapshot] {
        snapshots.sorted { lhs, rhs in
            let lhsPreferred = lhs.event.calendar.calendarIdentifier == preferredCalendarID
            let rhsPreferred = rhs.event.calendar.calendarIdentifier == preferredCalendarID
            if lhsPreferred != rhsPreferred {
                return lhsPreferred && !rhsPreferred
            }

            let lhsActive = lhs.event.endDate ?? lhs.event.startDate ?? .distantPast
            let rhsActive = rhs.event.endDate ?? rhs.event.startDate ?? .distantPast
            if lhsActive != rhsActive {
                return lhsActive > rhsActive
            }

            let lhsIdentifier = lhs.event.eventIdentifier ?? ""
            let rhsIdentifier = rhs.event.eventIdentifier ?? ""
            return lhsIdentifier < rhsIdentifier
        }
    }

    func sortManagedFootballEvents(
        _ events: [EKEvent],
        preferredCalendarID: String?
    ) -> [EKEvent] {
        events.sorted { lhs, rhs in
            let lhsPreferred = lhs.calendar.calendarIdentifier == preferredCalendarID
            let rhsPreferred = rhs.calendar.calendarIdentifier == preferredCalendarID
            if lhsPreferred != rhsPreferred {
                return lhsPreferred && !rhsPreferred
            }

            let lhsActive = lhs.endDate ?? lhs.startDate ?? .distantPast
            let rhsActive = rhs.endDate ?? rhs.startDate ?? .distantPast
            if lhsActive != rhsActive {
                return lhsActive > rhsActive
            }

            let lhsIdentifier = lhs.eventIdentifier ?? ""
            let rhsIdentifier = rhs.eventIdentifier ?? ""
            return lhsIdentifier < rhsIdentifier
        }
    }

    func managedFootballReference(for event: EKEvent) -> ManagedFootballFixtureReference? {
        if let legacyReference = ManagedFootballFixtureReference.parse(from: event.url) {
            return legacyReference
        }

        return managedFootballRecord(for: event)?.reference
    }

    func footballMatch(for event: EKEvent) -> FootballFixtureMatch? {
        if let reference = managedFootballReference(for: event),
           let match = footballMatchForManagedReference(reference) {
            return match
        }

        if let cachedMatch = matchedFootballFixture(
            for: event,
            in: Array(footballMatchesByID.values)
        ) {
            return cachedMatch
        }

        return matchedFootballFixture(for: event, in: managedFootballMatches)
    }

    func managedFootballRecord(for event: EKEvent) -> ManagedFootballEventRecord? {
        let eventIdentifier = event.eventIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let eventUID = normalizedEventUID(for: event)
        if let directRecord = managedFootballEventRecords.first(where: { record in
            if let eventUID, record.eventUID == eventUID {
                return true
            }

            if let eventIdentifier, record.eventIdentifier == eventIdentifier {
                return true
            }

            return false
        }) {
            return directRecord
        }

        guard let eventStartDate = event.startDate else { return nil }
        let nearbyRecords = managedFootballEventRecords.filter { record in
            record.calendarIdentifier == event.calendar.calendarIdentifier
                && abs(record.startDate.timeIntervalSince(eventStartDate)) <= Self.footballManagedEventMatchingTolerance
        }

        if nearbyRecords.count == 1 {
            return nearbyRecords[0]
        }

        let eventTitle = normalizedTitle(event.title)
        let titleMatchedRecords = nearbyRecords.filter { record in
            guard let match = footballMatchForManagedReference(record.reference) else { return false }
            return normalizedTitle(FootballFixtureFormatter.calendarTitle(for: match)) == eventTitle
        }

        if titleMatchedRecords.count == 1 {
            return titleMatchedRecords[0]
        }

        return nil
    }

    func resolveManagedFootballEvent(for record: ManagedFootballEventRecord) -> EKEvent? {
        if let eventIdentifier = record.eventIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !eventIdentifier.isEmpty,
           let event = eventStore.calendarItem(withIdentifier: eventIdentifier) as? EKEvent {
            return event
        }

        let calendar = Calendar.current
        let searchStart = calendar.date(byAdding: .day, value: -3, to: record.startDate) ?? record.startDate.addingTimeInterval(-3 * 86_400)
        let searchEnd = calendar.date(byAdding: .day, value: 3, to: record.startDate) ?? record.startDate.addingTimeInterval(3 * 86_400)
        let targetCalendars = eventStore.calendars(for: .event).filter { $0.calendarIdentifier == record.calendarIdentifier }
        let predicate = eventStore.predicateForEvents(
            withStart: searchStart,
            end: searchEnd,
            calendars: targetCalendars.isEmpty ? nil : targetCalendars
        )
        let candidates = eventStore.events(matching: predicate)

        if let eventUID = record.eventUID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !eventUID.isEmpty,
           let matchedByUID = candidates.first(where: { normalizedEventUID(for: $0) == eventUID }) {
            return matchedByUID
        }

        if let eventIdentifier = record.eventIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !eventIdentifier.isEmpty,
           let matchedByIdentifier = candidates.first(where: { $0.eventIdentifier == eventIdentifier }) {
            return matchedByIdentifier
        }

        let kickoffMatchedCandidates = candidates.filter { candidate in
            guard let candidateStartDate = candidate.startDate else { return false }
            return abs(candidateStartDate.timeIntervalSince(record.startDate)) <= Self.footballManagedEventMatchingTolerance
        }

        if kickoffMatchedCandidates.count == 1 {
            return kickoffMatchedCandidates[0]
        }

        if let match = footballMatchForManagedReference(record.reference) {
            let expectedTitle = normalizedTitle(FootballFixtureFormatter.calendarTitle(for: match))
            let titleMatchedCandidates = kickoffMatchedCandidates.filter { candidate in
                normalizedTitle(candidate.title) == expectedTitle
            }
            if titleMatchedCandidates.count == 1 {
                return titleMatchedCandidates[0]
            }
        }

        return nil
    }

    func managedFootballEventRecord(
        for event: EKEvent,
        reference: ManagedFootballFixtureReference
    ) -> ManagedFootballEventRecord {
        ManagedFootballEventRecord(
            matchID: reference.matchID,
            competitionSlug: reference.competitionSlug,
            calendarIdentifier: event.calendar.calendarIdentifier,
            eventIdentifier: event.eventIdentifier,
            eventUID: normalizedEventUID(for: event),
            startDate: event.startDate ?? fixedSecondNow()
        )
    }

    func upsertManagedFootballEventRecord(for event: EKEvent, reference: ManagedFootballFixtureReference) {
        var recordsByReference = Dictionary(uniqueKeysWithValues: managedFootballEventRecords.map { ($0.reference, $0) })
        recordsByReference[reference] = managedFootballEventRecord(for: event, reference: reference)
        persistManagedFootballEventRecords(Array(recordsByReference.values))
    }

    func removeManagedFootballEventRecord(for reference: ManagedFootballFixtureReference) {
        persistManagedFootballEventRecords(
            managedFootballEventRecords.filter { $0.reference != reference }
        )
    }

    func persistManagedFootballEventRecords(_ records: [ManagedFootballEventRecord]) {
        let normalizedRecords = deduplicatedManagedFootballEventRecords(records)
        guard normalizedRecords != managedFootballEventRecords else { return }

        invalidateManagedFootballSnapshotCache()
        managedFootballEventRecords = normalizedRecords
        if normalizedRecords.isEmpty {
            defaults.removeObject(forKey: DefaultsKeys.managedFootballEventRecords)
            return
        }

        if let data = try? JSONEncoder().encode(normalizedRecords) {
            defaults.set(data, forKey: DefaultsKeys.managedFootballEventRecords)
        }
    }

    func deduplicatedManagedFootballEventRecords(_ records: [ManagedFootballEventRecord]) -> [ManagedFootballEventRecord] {
        var deduplicatedByReference: [ManagedFootballFixtureReference: ManagedFootballEventRecord] = [:]

        for record in records {
            let reference = record.reference
            if let existingRecord = deduplicatedByReference[reference] {
                let existingHasUID = !(existingRecord.eventUID ?? "").isEmpty
                let candidateHasUID = !(record.eventUID ?? "").isEmpty
                if existingHasUID == candidateHasUID {
                    if record.startDate >= existingRecord.startDate {
                        deduplicatedByReference[reference] = record
                    }
                } else if candidateHasUID {
                    deduplicatedByReference[reference] = record
                }
            } else {
                deduplicatedByReference[reference] = record
            }
        }

        return deduplicatedByReference.values.sorted { lhs, rhs in
            if lhs.competitionSlug != rhs.competitionSlug {
                return lhs.competitionSlug < rhs.competitionSlug
            }
            if lhs.startDate != rhs.startDate {
                return lhs.startDate < rhs.startDate
            }
            return lhs.matchID < rhs.matchID
        }
    }

    nonisolated static func isManagedFootballEventWithinSuggestionWindow(
        startDate: Date,
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Bool {
        let trackedLookbackDays = FootballCompetitionPreset.suggestionWindowLookbackDays
        let trackedLookaheadDays = FootballCompetitionPreset.suggestionWindowLookaheadDays
        let lowerBound = calendar.date(byAdding: .day, value: -trackedLookbackDays, to: now) ?? now
        let upperBound = calendar.date(byAdding: .day, value: trackedLookaheadDays, to: now) ?? now
        return startDate >= lowerBound && startDate <= upperBound
    }

    func revealCalendarEvent(_ event: EKEvent) -> Bool {
        guard let eventUID = normalizedEventUID(for: event) else { return false }

        let script = Self.calendarRevealScript(eventUID: eventUID)

        return Self.runAppleScript(script)
    }

    func normalizedEventUID(for event: EKEvent) -> String? {
        let externalID = event.calendarItemExternalIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let externalID, !externalID.isEmpty {
            return externalID
        }

        let fallbackID = event.eventIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fallbackID, !fallbackID.isEmpty {
            return fallbackID
        }

        return nil
    }

    func openCalendarApplication() -> Bool {
        let calendarAppURL = URL(fileURLWithPath: "/System/Applications/Calendar.app", isDirectory: true)
        let configuration = NSWorkspace.OpenConfiguration()
        AlertCalendarWorkspace.openApplication(at: calendarAppURL, configuration: configuration) { _, error in
            if error != nil {
                Task { @MainActor in
                    AlertCalendarWorkspace.open(calendarAppURL)
                }
            }
        }
        return true
    }

    nonisolated static func calendarRevealScript(eventUID: String) -> String {
        """
        tell application "Calendar"
            activate
            repeat with targetCalendar in every calendar
                try
                    set targetEvent to first event of targetCalendar whose uid is \(appleScriptStringLiteral(eventUID))
                    show targetEvent
                    return
                end try
            end repeat
            error "Could not find the requested event."
        end tell
        """
    }

    nonisolated static func runAppleScript(_ source: String) -> Bool {
        AlertCalendarProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", source],
            waitUntilExit: true,
            redirectsOutputToNull: false
        ) == 0
    }

    nonisolated static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    func footballTargetCalendars() -> [EKCalendar] {
        let allEventCalendars = eventStore.calendars(for: .event)
            .filter { $0.type != .subscription && $0.type != .birthday }

        let writableCalendars = allEventCalendars
            .filter(\.allowsContentModifications)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        if !writableCalendars.isEmpty {
            return writableCalendars
        }

        if let defaultCalendar = eventStore.defaultCalendarForNewEvents,
           defaultCalendar.type != .subscription,
           defaultCalendar.type != .birthday {
            let candidateCalendars = ([defaultCalendar] + allEventCalendars).reduce(into: [EKCalendar]()) { partialResult, calendar in
                guard partialResult.contains(where: { $0.calendarIdentifier == calendar.calendarIdentifier }) == false else { return }
                partialResult.append(calendar)
            }
            return candidateCalendars.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }

        return allEventCalendars.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    func resolvedFootballTargetCalendar() -> EKCalendar? {
        let writableCalendars = footballTargetCalendars()

        guard !writableCalendars.isEmpty else {
            defaults.removeObject(forKey: DefaultsKeys.footballTargetCalendarID)
            return nil
        }

        if let storedID = defaults.string(forKey: DefaultsKeys.footballTargetCalendarID),
           let stored = writableCalendars.first(where: { $0.calendarIdentifier == storedID }) {
            return stored
        }

        let selectedIDs = selectedCalendarIDs(for: .event)
        if let selected = writableCalendars.first(where: { selectedIDs.contains($0.calendarIdentifier) }) {
            defaults.set(selected.calendarIdentifier, forKey: DefaultsKeys.footballTargetCalendarID)
            return selected
        }

        if let defaultCalendar = eventStore.defaultCalendarForNewEvents,
           let resolvedDefaultCalendar = writableCalendars.first(where: { $0.calendarIdentifier == defaultCalendar.calendarIdentifier }) {
            defaults.set(resolvedDefaultCalendar.calendarIdentifier, forKey: DefaultsKeys.footballTargetCalendarID)
            return resolvedDefaultCalendar
        }

        if let defaultCalendar = eventStore.defaultCalendarForNewEvents,
           defaultCalendar.type != .subscription,
           defaultCalendar.type != .birthday {
            defaults.set(defaultCalendar.calendarIdentifier, forKey: DefaultsKeys.footballTargetCalendarID)
            return defaultCalendar
        }

        let fallback = writableCalendars[0]
        defaults.set(fallback.calendarIdentifier, forKey: DefaultsKeys.footballTargetCalendarID)
        return fallback
    }

    func ensureFootballTargetCalendarIsSelected(_ calendarIdentifier: String) {
        var selectedIDs = selectedCalendarIDs(for: .event)
        guard !selectedIDs.contains(calendarIdentifier) else { return }
        selectedIDs.insert(calendarIdentifier)
        defaults.set(Array(selectedIDs), forKey: DefaultsKeys.selectedEventCalendarIDs)
    }

    func footballMatchForManagedReference(_ reference: ManagedFootballFixtureReference) -> FootballFixtureMatch? {
        footballMatchesByID[reference.matchID]
    }


}
