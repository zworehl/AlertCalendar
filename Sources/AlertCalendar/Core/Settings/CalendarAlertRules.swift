import Foundation

enum CalendarAlertRuleScope: String, Codable, CaseIterable, Identifiable {
    case allEvents
    case invitationsOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allEvents:
            return "All events"
        case .invitationsOnly:
            return "Invitations only"
        }
    }
}

enum CalendarAlertTimingKind: String, Codable {
    case relative
    case timeToLeave
}

struct CalendarEventAlert: Codable, Equatable, Hashable, Identifiable {
    static let maximumAbsoluteOffsetSeconds = 365 * 24 * 60 * 60

    var id: UUID
    var timingKind: CalendarAlertTimingKind
    var relativeOffsetSeconds: Int

    init(
        id: UUID = UUID(),
        timingKind: CalendarAlertTimingKind = .relative,
        relativeOffsetSeconds: Int = -15 * 60
    ) {
        self.id = id
        self.timingKind = timingKind
        self.relativeOffsetSeconds = relativeOffsetSeconds
    }

    static var fifteenMinutesBefore: CalendarEventAlert {
        CalendarEventAlert(relativeOffsetSeconds: -15 * 60)
    }

    static var allDayOneDayBeforeAtNine: CalendarEventAlert {
        CalendarEventAlert(relativeOffsetSeconds: -15 * 60 * 60)
    }

    var normalized: CalendarEventAlert {
        var result = self
        result.relativeOffsetSeconds = max(
            -Self.maximumAbsoluteOffsetSeconds,
            min(Self.maximumAbsoluteOffsetSeconds, relativeOffsetSeconds)
        )
        return result
    }

    var semanticKey: String {
        let normalized = normalized
        return [
            normalized.timingKind.rawValue,
            String(normalized.relativeOffsetSeconds),
        ].joined(separator: "|")
    }

    var maximumLeadTime: TimeInterval {
        switch timingKind {
        case .relative:
            return TimeInterval(max(0, -normalized.relativeOffsetSeconds))
        case .timeToLeave:
            return 12 * 60 * 60
        }
    }

    func timingDescription(isAllDay: Bool = false) -> String {
        if timingKind == .timeToLeave {
            return "Time to Leave"
        }

        let offset = normalized.relativeOffsetSeconds
        if isAllDay {
            switch offset {
            case 9 * 60 * 60:
                return "On day of event (9:00 AM)"
            case -15 * 60 * 60:
                return "1 day before (9:00 AM)"
            case -39 * 60 * 60:
                return "2 days before (9:00 AM)"
            case -159 * 60 * 60:
                return "1 week before (9:00 AM)"
            default:
                break
            }
        }

        guard offset != 0 else { return "At time of event" }
        let absoluteSeconds = abs(offset)
        let value: Int
        let unit: String

        if absoluteSeconds % (7 * 24 * 60 * 60) == 0 {
            value = absoluteSeconds / (7 * 24 * 60 * 60)
            unit = value == 1 ? "week" : "weeks"
        } else if absoluteSeconds % (24 * 60 * 60) == 0 {
            value = absoluteSeconds / (24 * 60 * 60)
            unit = value == 1 ? "day" : "days"
        } else if absoluteSeconds % (60 * 60) == 0 {
            value = absoluteSeconds / (60 * 60)
            unit = value == 1 ? "hour" : "hours"
        } else {
            value = max(1, absoluteSeconds / 60)
            unit = value == 1 ? "minute" : "minutes"
        }

        return "\(value) \(unit) \(offset < 0 ? "before" : "after")"
    }
}

struct CalendarAlertRule: Codable, Equatable, Identifiable {
    var calendarID: String
    var isEnabled: Bool
    var scope: CalendarAlertRuleScope
    var overwriteExistingAlerts: Bool
    var timedEventAlerts: [CalendarEventAlert]
    var allDayEventAlerts: [CalendarEventAlert]

    var id: String { calendarID }

    init(
        calendarID: String,
        isEnabled: Bool = true,
        scope: CalendarAlertRuleScope = .invitationsOnly,
        overwriteExistingAlerts: Bool = false,
        timedEventAlerts: [CalendarEventAlert] = [.fifteenMinutesBefore],
        allDayEventAlerts: [CalendarEventAlert] = [.allDayOneDayBeforeAtNine]
    ) {
        self.calendarID = calendarID
        self.isEnabled = isEnabled
        self.scope = scope
        self.overwriteExistingAlerts = overwriteExistingAlerts
        self.timedEventAlerts = timedEventAlerts
        self.allDayEventAlerts = allDayEventAlerts
    }

    var normalized: CalendarAlertRule? {
        guard let calendarID = AlertCalendarString.trimmedNonEmpty(calendarID) else { return nil }
        var result = self
        result.calendarID = calendarID
        result.timedEventAlerts = Self.normalizedAlerts(timedEventAlerts)
        result.allDayEventAlerts = Self.normalizedAlerts(allDayEventAlerts)
        return result
    }

    var maximumLeadTime: TimeInterval {
        (timedEventAlerts + allDayEventAlerts)
            .map(\.maximumLeadTime)
            .max() ?? 0
    }

    func alerts(isAllDay: Bool) -> [CalendarEventAlert] {
        isAllDay ? allDayEventAlerts : timedEventAlerts
    }

    static func normalized(
        _ rules: [CalendarAlertRule],
        validCalendarIDs: Set<String>? = nil
    ) -> [CalendarAlertRule] {
        var seenCalendarIDs: Set<String> = []
        var result: [CalendarAlertRule] = []

        for rule in rules {
            guard let normalized = rule.normalized else { continue }
            if let validCalendarIDs, !validCalendarIDs.contains(normalized.calendarID) {
                continue
            }
            guard seenCalendarIDs.insert(normalized.calendarID).inserted else { continue }
            result.append(normalized)
        }

        return result
    }

    private static func normalizedAlerts(_ alerts: [CalendarEventAlert]) -> [CalendarEventAlert] {
        var seenKeys: Set<String> = []
        var result: [CalendarEventAlert] = []

        for alert in alerts.map(\.normalized) {
            guard seenKeys.insert(alert.semanticKey).inserted else { continue }
            result.append(alert)
        }

        return result
    }
}
