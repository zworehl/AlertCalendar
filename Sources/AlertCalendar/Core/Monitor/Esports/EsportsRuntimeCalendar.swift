import AppKit
import EventKit
import Foundation

extension EsportsRuntime {
    static func competitionKey(for match: EsportsMatch) -> String? {
        match.competitionKey
    }

    func canAddMatch(_ match: EsportsMatch) -> Bool {
        match.providerID > 0 && match.game.providerSlug != nil && (match.beginAt ?? match.scheduledAt) != nil
            && (match.status == .scheduled || match.status == .running)
    }

    func presence(of match: EsportsMatch) -> EsportsMatchPresence {
        if records[match.id] != nil { return .managed }
        if !localCandidates(for: match).isEmpty { return .external }
        return .absent
    }

    /// A possible duplicate is deliberately read-only. Temporal overlap is a
    /// review signal, never evidence that a manual event belongs to PandaScore.
    func localCandidates(for match: EsportsMatch) -> [LocalGamingCalendarEvent] {
        localEvents.filter { local in
            if local.providerMatchID == match.id { return true }
            guard local.game == match.game, let start = match.beginAt ?? match.scheduledAt else { return false }
            let matchEnd = match.endAt.flatMap { $0 > start ? $0 : nil } ?? start.addingTimeInterval(7_200)
            let localEnd = local.endDate ?? local.startDate.addingTimeInterval(7_200)
            return (local.startDate < matchEnd && localEnd > start)
                || abs(local.startDate.timeIntervalSince(start)) <= 5_400
        }
    }

    @discardableResult
    func addMatch(_ match: EsportsMatch) async -> Bool { addMatchNow(match) }

    @discardableResult
    func addMatchNow(_ match: EsportsMatch) -> Bool {
        guard !stopped else { return false }
        restoreRecords()
        guard presence(of: match) == .absent else { return true }
        guard hasEventsAccess, canAddMatch(match), let start = match.beginAt ?? match.scheduledAt else { return false }
        guard let calendar = calendarSource.writableCalendar(id: settings.targetCalendarID) else {
            errorMessage = L10n.text("Choose a writable event calendar before adding esports matches."); return false
        }
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        let calendarID = settings.targetCalendarID
        let content = EsportsEventContent(match: match, start: start, alertLeadMinutes: settings.alertLeadMinutes)
        content.apply(to: event)
        do {
            try mutations.perform { try $0.save(event) }
            records[match.id] = makeRecord(for: event, match: match, calendarID: calendarID, content: content)
            dismissedMatchIDs.remove(match.id)
            merge([match]); persistRecords(); publishMatches(); scheduleCacheSave()
            onCalendarAdded?(calendarID)
            refreshLocalEvents()
            return true
        } catch {
            errorMessage = L10n.text("Could not save the esports match to Calendar."); return false
        }
    }

    @discardableResult
    func removeMatch(_ match: EsportsMatch) -> Bool {
        guard !stopped else { return false }
        restoreRecords()
        guard let record = records[match.id] else { return true }
        guard hasEventsAccess else { return false }
        guard let event = calendarSource.event(for: record) else {
            // A transient/stale EventKit lookup is not proof that the event was deleted.
            errorMessage = L10n.text("Could not find the managed esports event in Calendar."); return false
        }
        do {
            try mutations.perform { try $0.remove(event) }
            records[match.id] = nil
            dismissedMatchIDs.insert(match.id)
            persistRecords(); publishMatches(); refreshLocalEvents()
            return true
        } catch {
            errorMessage = L10n.text("Could not remove the esports match from Calendar."); return false
        }
    }

    func synchronizeManagedMatches(_ fresh: [EsportsMatch]) {
        guard hasEventsAccess, !stopped else { return }
        var changed = false
        for match in fresh {
            guard let record = records[match.id], let event = calendarSource.event(for: record),
                  record.applied.stillMatches(event) else { continue }
            // Postponed/canceled records stay owned and visible; absence never removes them.
            let start = match.beginAt ?? match.scheduledAt ?? record.startDate
            let content = EsportsEventContent(match: match, start: start, alertLeadMinutes: settings.alertLeadMinutes)
            guard content != record.applied else { continue }
            do {
                try mutations.perform { batch in content.apply(to: event); try batch.save(event) }
                records[match.id] = makeRecord(for: event, match: match, calendarID: record.calendarID, content: content)
                changed = true
            } catch { errorMessage = L10n.text("Some managed esports events could not be updated.") }
        }
        if changed { persistRecords(); publishMatches() }
    }

    func autoAdd(_ fresh: [EsportsMatch]) {
        guard hasEventsAccess, !settings.autoAddCompetitionIDs.isEmpty, !stopped else { return }
        for match in fresh {
            guard let key = Self.competitionKey(for: match), settings.autoAddCompetitionIDs.contains(key),
                  !dismissedMatchIDs.contains(match.id), records[match.id] == nil,
                  let start = match.beginAt ?? match.scheduledAt, start >= now() else { continue }
            _ = addMatchNow(match)
        }
    }

    func restoreRecords() {
        guard !didRestoreRecords else { return }
        didRestoreRecords = true
        if let data = defaults.data(forKey: Self.recordsKey),
           let saved = try? JSONDecoder().decode([ManagedEsportsEventRecord].self, from: data) {
            records = Dictionary(saved.map { ($0.matchID, $0) }, uniquingKeysWith: { first, _ in first })
            merge(saved.compactMap(\.cachedMatch))
        }
        dismissedMatchIDs = Set(defaults.stringArray(forKey: Self.dismissedKey) ?? [])
        publishMatches()
    }

    func persistRecords() {
        if let data = try? JSONEncoder().encode(records.values.sorted { $0.matchID < $1.matchID }) {
            defaults.set(data, forKey: Self.recordsKey)
        }
        defaults.set(dismissedMatchIDs.sorted(), forKey: Self.dismissedKey)
    }

    func makeRecord(for event: EKEvent, match: EsportsMatch, calendarID: String, content: EsportsEventContent) -> ManagedEsportsEventRecord {
        ManagedEsportsEventRecord(matchID: match.id, calendarID: calendarID, eventIdentifier: event.eventIdentifier,
            eventUID: event.calendarItemExternalIdentifier, startDate: content.start, applied: content, cachedMatch: match)
    }

    func openLocalEvent(_ event: LocalGamingCalendarEvent) {
        reveal(eventUID: event.eventUID ?? event.eventIdentifier, fallbackURL: event.sourceURL)
    }

    func openMatch(_ match: EsportsMatch) {
        if let record = records[match.id] {
            reveal(eventUID: record.eventUID ?? record.eventIdentifier, fallbackURL: nil)
        } else if !localCandidates(for: match).isEmpty {
            let candidates = localCandidates(for: match)
            if candidates.count == 1 { openLocalEvent(candidates[0]) }
            else { reveal(eventUID: nil, fallbackURL: nil) }
        } else if let url = EsportsStreamURLPolicy.safeURL(match.streamURL) { _ = AlertCalendarWorkspace.open(url) }
    }

    func reveal(eventUID: String?, fallbackURL: URL?) {
        openTask?.cancel()
        openTask = Task { @MainActor in
            if let eventUID, !eventUID.isEmpty,
               await CalendarMonitor.runAppleScript(CalendarMonitor.calendarRevealScript(eventUID: eventUID)) { return }
            guard !Task.isCancelled, !stopped else { return }
            if let fallbackURL, ["http", "https"].contains(fallbackURL.scheme?.lowercased() ?? "") {
                _ = AlertCalendarWorkspace.open(fallbackURL)
            } else {
                _ = AlertCalendarWorkspace.open(URL(fileURLWithPath: "/System/Applications/Calendar.app", isDirectory: true))
            }
        }
    }
}
