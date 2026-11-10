import EventKit
import Foundation

extension EsportsRuntime {
    func performRefresh(force: Bool, revision: Int) async {
        guard current(revision) else { return }
        isRefreshing = true
        restoreRecords()
        // Local calendars become useful before any network await.
        if force || lastLocalRefresh.map({ now().timeIntervalSince($0) >= 300 }) ?? true {
            refreshLocalEvents(); lastLocalRefresh = now()
        }
        if !didRestore {
            let cached = await cacheStore?.load() ?? []
            guard current(revision) else { return }
            merge(cached); publishMatches()
            didRestore = true
        }
        guard current(revision) else { return }
        guard !settings.providerGames.isEmpty else { return }
        let window = dateWindow()
        var freshMatches: [EsportsMatch] = []
        var completed = true
        var attempted = false
        var issueMessage: String?
        for game in settings.providerGames.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard current(revision) else { return }
            if let retry = providerRetryAt[game], retry > now() {
                completed = false
                issueMessage = L10n.text("Some esports calendar events are unavailable. Cached events remain available.")
                continue
            }
            if !force, providerRetryAt[game] == nil, let last = lastProviderFetch[game], now().timeIntervalSince(last) < 7_200 { continue }
            attempted = true; lastProviderFetch[game] = now()
            do {
                let tracked = records.keys.compactMap { matchesByID[$0] }.filter { $0.game == game }.map(\.providerID).sorted()
                let result = try await client.load(game: game, from: window.0, to: window.1, trackedIDs: tracked)
                guard current(revision) else { return }
                merge(result.matches); freshMatches += result.matches
                completed = completed && result.isComplete
                if !result.isComplete {
                    issueMessage = L10n.text("Some esports calendar events are unavailable. Cached events remain available.")
                    providerRetryAt[game] = result.issues.compactMap(\.retryAt).max() ?? now().addingTimeInterval(300)
                } else {
                    providerRetryAt[game] = nil
                    validatedAtByGame[game] = result.fetchedAt
                }
            } catch {
                guard current(revision) else { return }
                completed = false; issueMessage = safeError(error)
                providerRetryAt[game] = retryDate(for: error) ?? now().addingTimeInterval(300)
            }
        }
        guard current(revision) else { return }
        publishMatches()
        if attempted {
            if completed, settings.providerGames.allSatisfy({ validatedAtByGame[$0] != nil }) {
                lastValidatedAt = settings.providerGames.compactMap { validatedAtByGame[$0] }.min()
            }
            errorMessage = issueMessage
            scheduleCacheSave()
        }
        // A cache restore or absent list entry can never create/delete Calendar events.
        synchronizeManagedMatches(freshMatches)
        autoAdd(freshMatches)
    }

    func retryDate(for error: any Error) -> Date? {
        switch error as? EsportsFeedError {
        case .rateLimited(let date): date
        case .retryDeferred(_, let date), .requestBudget(let date): date
        default: nil
        }
    }

    func refreshLocalEvents() {
        guard hasEventsAccess, !selectedCalendarIDs.isEmpty else {
            if !localEvents.isEmpty { localEvents = [] }; return
        }
        let window = dateWindow()
        let events = calendarSource.events(from: window.0, to: window.1, calendarIDs: selectedCalendarIDs)
        var values: [LocalGamingCalendarEvent] = []
        var seen: Set<String> = []
        for event in events {
            guard let start = event.startDate, let calendar = event.calendar,
                  selectedCalendarIDs.contains(calendar.calendarIdentifier),
                  let classification = GamingCalendarClassifier.classify(title: event.title ?? "", notes: event.notes, url: event.url, calendarName: calendar.title),
                  EsportsCatalog.supports(classification.0),
                  classification.1 == .competitive else { continue }
            let reference = GamingCalendarClassifier.providerReference(in: event.notes)
            if let reference, let record = records[reference], record.calendarID == calendar.calendarIdentifier,
               event.notes?.contains(ManagedEsportsEventRecord.ownershipMarker) == true { continue }
            let identity = event.eventIdentifier ?? event.calendarItemExternalIdentifier ?? "\(calendar.calendarIdentifier):\(event.title ?? "")"
            let id = "\(identity):\(event.occurrenceDate ?? start)"
            guard seen.insert(id).inserted else { continue }
            values.append(LocalGamingCalendarEvent(id: id, game: classification.0, title: event.title ?? "", startDate: start,
                endDate: event.endDate, isAllDay: event.isAllDay, calendarID: calendar.calendarIdentifier,
                calendarName: calendar.title, sourceURL: event.url, eventIdentifier: event.eventIdentifier,
                eventUID: event.calendarItemExternalIdentifier, kind: classification.1, providerMatchID: reference))
        }
        values.sort { $0.startDate == $1.startDate ? $0.id < $1.id : $0.startDate < $1.startDate }
        if values != localEvents { localEvents = values }
    }
}
