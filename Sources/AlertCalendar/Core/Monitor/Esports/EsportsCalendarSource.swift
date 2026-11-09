import EventKit
import Foundation

@MainActor
protocol EsportsCalendarReading {
    func events(from: Date, to: Date, calendarIDs: Set<String>) -> [EKEvent]
    func writableCalendar(id: String) -> EKCalendar?
    func event(for record: ManagedEsportsEventRecord) -> EKEvent?
}

@MainActor
struct EventKitEsportsCalendarSource: EsportsCalendarReading {
    let eventStore: EKEventStore

    func events(from: Date, to: Date, calendarIDs: Set<String>) -> [EKEvent] {
        // An empty Focus selection means no events, never all calendars.
        guard !calendarIDs.isEmpty else { return [] }
        let calendars = eventStore.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        return eventStore.events(matching: eventStore.predicateForEvents(withStart: from, end: to, calendars: calendars))
    }

    func writableCalendar(id: String) -> EKCalendar? {
        guard !id.isEmpty, let calendar = eventStore.calendar(withIdentifier: id),
              calendar.allowedEntityTypes.contains(.event), calendar.allowsContentModifications,
              !calendar.isImmutable else { return nil }
        return calendar
    }

    func event(for record: ManagedEsportsEventRecord) -> EKEvent? {
        if let id = record.eventIdentifier, let event = eventStore.event(withIdentifier: id), owns(event, record) { return event }
        let candidates = events(from: record.startDate.addingTimeInterval(-86_400),
                                to: record.startDate.addingTimeInterval(86_400), calendarIDs: [record.calendarID])
            .filter { owns($0, record) }
        // Duplicate or ambiguous identities must never be silently adopted.
        return candidates.count == 1 ? candidates.first : nil
    }

    private func owns(_ event: EKEvent, _ record: ManagedEsportsEventRecord) -> Bool {
        event.calendar?.calendarIdentifier == record.calendarID
            && GamingCalendarClassifier.providerReference(in: event.notes) == record.matchID
            && event.notes?.contains(ManagedEsportsEventRecord.ownershipMarker) == true
    }
}

struct ManagedEsportsEventRecord: Codable, Equatable, Sendable {
    static let ownershipMarker = "Managed by AlertCalendar · Esports v1"
    let matchID: String
    let calendarID: String
    let eventIdentifier: String?
    let eventUID: String?
    let startDate: Date
    let applied: EsportsEventContent
    var cachedMatch: EsportsMatch? = nil
}

struct EsportsEventContent: Codable, Equatable, Sendable {
    let title: String
    let start: Date
    let end: Date
    let notes: String
    let alertLeadMinutes: Int

    init(match: EsportsMatch, start: Date, alertLeadMinutes: Int) {
        self.start = start
        let knownEnd = match.endAt.flatMap { $0 > start ? $0 : nil }
        self.end = knownEnd ?? start.addingTimeInterval(7_200)
        self.title = "[\(match.game.displayName)] \(match.name)"
        self.alertLeadMinutes = match.status == .canceled || match.status == .postponed ? 0 : alertLeadMinutes
        var lines = [ManagedEsportsEventRecord.ownershipMarker, match.id, EsportsMatch.sourceAttribution]
        if !match.competitionName.isEmpty { lines.append(match.competitionName) }
        lines.append("Status: \(match.status.rawValue)")
        if let games = match.numberOfGames {
            switch match.matchType {
            case "best_of": lines.append("Series: best of \(games)")
            case "first_to": lines.append("Series: first to \(games)")
            default: lines.append("Series: \(games) games")
            }
        }
        if !match.results.isEmpty {
            let scores = match.opponents.compactMap { opponent in match.score(for: opponent).map { "\(opponent.name): \($0)" } }
            if !scores.isEmpty { lines.append(scores.joined(separator: " · ")) }
        }
        if knownEnd == nil { lines.append("End time is an estimate (2 hours); series duration may vary.") }
        if let url = EsportsStreamURLPolicy.safeURL(match.streamURL) { lines.append(url.absoluteString) }
        self.notes = lines.joined(separator: "\n")
    }

    @MainActor func apply(to event: EKEvent) {
        event.title = title; event.startDate = start; event.endDate = end; event.notes = notes
        event.alarms = alertLeadMinutes > 0 ? [EKAlarm(relativeOffset: -Double(alertLeadMinutes) * 60)] : nil
    }

    @MainActor func stillMatches(_ event: EKEvent) -> Bool {
        guard event.title == title, event.startDate == start, event.endDate == end, event.notes == notes else { return false }
        let alarms = event.alarms ?? []
        if alertLeadMinutes == 0 { return alarms.isEmpty }
        return alarms.count == 1 && alarms[0].absoluteDate == nil
            && abs(alarms[0].relativeOffset + Double(alertLeadMinutes) * 60) < 1
    }
}
