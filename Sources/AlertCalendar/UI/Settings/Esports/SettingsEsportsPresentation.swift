import Foundation

enum SettingsEsportsBrowseMode: String, CaseIterable, Identifiable {
    case schedule, nowAndNextDay, added
    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: L10n.text("Schedule and results")
        case .nowAndNextDay: L10n.text("Now + Next 24h")
        case .added: L10n.text("Added Matches")
        }
    }

    var symbolName: String {
        switch self {
        case .schedule: "trophy"
        case .nowAndNextDay: "clock"
        case .added: "calendar.badge.checkmark"
        }
    }
}

struct SettingsEsportsCompetition: Identifiable, Equatable {
    let id: String
    let name: String
    let game: EsportsGame
}

enum SettingsEsportsPresentation {
    static func competitions(in matches: [EsportsMatch], game: EsportsGame?) -> [SettingsEsportsCompetition] {
        var unique: [String: SettingsEsportsCompetition] = [:]
        for match in matches where game == nil || match.game == game {
            guard EsportsCatalog.supports(match.game) else { continue }
            guard let competitionID = match.competitionID else { continue }
            let key = "\(match.game.rawValue):\(competitionID)"
            guard !match.competitionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            unique[key] = SettingsEsportsCompetition(id: key, name: match.competitionName, game: match.game)
        }
        return unique.values.sorted {
            ($0.name.localizedStandardCompare($1.name) == .orderedAscending)
                || ($0.name == $1.name && $0.id < $1.id)
        }
    }

    static func startDate(for match: EsportsMatch) -> Date? {
        guard match.status != .postponed else { return nil }
        return match.beginAt ?? match.scheduledAt
    }

    static func visibleMatches(
        _ matches: [EsportsMatch], game: EsportsGame?, competitionKey: String?,
        mode: SettingsEsportsBrowseMode, preferences: EsportsSettings, now: Date,
        managedIDs: Set<String>, pending: [String: SettingsPendingItemChange<EsportsMatch>]
    ) -> [EsportsMatch] {
        var byID = Dictionary(matches.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for (id, change) in pending where change.mutation == .add { byID[id] = change.item }
        return byID.values.filter { match in
            guard EsportsCatalog.supports(match.game), game == nil || match.game == game else { return false }
            if let competitionKey {
                guard let id = match.competitionID,
                      competitionKey == "\(match.game.rawValue):\(id)" else { return false }
            }
            if mode == .added {
                return pending[match.id]?.mutation.makesItemPresent ?? managedIDs.contains(match.id)
            }
            if mode == .nowAndNextDay {
                if match.status == .running { return true }
                guard match.status == .scheduled, let date = startDate(for: match) else { return false }
                return date >= now && date <= now.addingTimeInterval(86_400)
            }
            if match.status == .running { return true }
            guard let date = startDate(for: match) else { return true }
            return isWithinWindow(start: date, end: match.endAt, preferences: preferences, now: now)
        }.sorted {
            let lhs = startDate(for: $0) ?? .distantFuture
            let rhs = startDate(for: $1) ?? .distantFuture
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
    }

    static func visibleLocalEvents(
        _ events: [LocalGamingCalendarEvent], game: EsportsGame?, mode: SettingsEsportsBrowseMode,
        preferences: EsportsSettings, now: Date
    ) -> [LocalGamingCalendarEvent] {
        events.filter { event in
            guard EsportsCatalog.supports(event.game), event.kind == .competitive,
                  game == nil || event.game == game else { return false }
            if mode == .nowAndNextDay {
                return event.startDate <= now.addingTimeInterval(86_400)
                    && (event.endDate ?? event.startDate) >= now
            }
            return isWithinWindow(start: event.startDate, end: event.endDate, preferences: preferences, now: now)
        }.sorted { $0.startDate == $1.startDate ? $0.id < $1.id : $0.startDate < $1.startDate }
    }

    static func isWithinWindow(start: Date, end: Date?, preferences: EsportsSettings, now: Date) -> Bool {
        let calendar = Calendar.autoupdatingCurrent
        let earliest = calendar.date(byAdding: .day, value: -preferences.lookbackDays, to: now) ?? now
        let latest = calendar.date(byAdding: .day, value: preferences.lookaheadDays, to: now) ?? now
        return (end ?? start) >= earliest && start <= latest
    }

    static func displayedScore(for opponent: EsportsOpponent, in match: EsportsMatch) -> Int? {
        guard match.status == .running || match.status == .finished,
              let score = match.score(for: opponent), score >= 0 else { return nil }
        return score
    }

    static func toggledPendingChanges(
        for match: EsportsMatch, presence: EsportsMatchPresence,
        changes: [String: SettingsPendingItemChange<EsportsMatch>]
    ) -> [String: SettingsPendingItemChange<EsportsMatch>] {
        guard presence == .absent || presence == .managed else {
            var result = changes
            result.removeValue(forKey: match.id)
            return result
        }
        var pending = SettingsPendingChanges()
        pending.esportsMatches = changes
        pending.toggleEsportsMatch(match, persistedIsPresent: presence == .managed)
        return pending.esportsMatches
    }

    static func canTogglePendingChange(
        presence: EsportsMatchPresence, pending: SettingsPendingItemChange<EsportsMatch>?,
        canAdd: Bool, canRemove: Bool
    ) -> Bool {
        if pending != nil { return true }
        if presence == .managed { return canRemove }
        if presence == .absent { return canAdd }
        return false
    }

    static func statusText(_ status: EsportsMatchStatus) -> String {
        switch status {
        case .scheduled: L10n.text("Scheduled")
        case .running: L10n.text("In progress")
        case .finished: L10n.text("Finished")
        case .canceled: L10n.text("Canceled")
        case .postponed: L10n.text("Postponed")
        case .unknown: L10n.text("Status unavailable")
        }
    }
}
