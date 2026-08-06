import Foundation

enum SettingsCalendarAlertPreset: String, Identifiable {
    case atTime
    case fiveMinutes
    case tenMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case oneDay
    case twoDays
    case oneWeek
    case timeToLeave
    case allDaySameDay
    case allDayOneDay
    case allDayTwoDays
    case allDayOneWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .atTime: return "At time of event"
        case .fiveMinutes: return "5 minutes before"
        case .tenMinutes: return "10 minutes before"
        case .fifteenMinutes: return "15 minutes before"
        case .thirtyMinutes: return "30 minutes before"
        case .oneHour: return "1 hour before"
        case .twoHours: return "2 hours before"
        case .oneDay: return "1 day before"
        case .twoDays: return "2 days before"
        case .oneWeek: return "1 week before"
        case .timeToLeave: return "Time to Leave"
        case .allDaySameDay: return "On day of event (9:00 AM)"
        case .allDayOneDay: return "1 day before (9:00 AM)"
        case .allDayTwoDays: return "2 days before (9:00 AM)"
        case .allDayOneWeek: return "1 week before (9:00 AM)"
        }
    }

    static func options(isAllDay: Bool) -> [SettingsCalendarAlertPreset] {
        if isAllDay {
            return [.allDaySameDay, .allDayOneDay, .allDayTwoDays, .allDayOneWeek]
        }
        return [
            .atTime, .fiveMinutes, .tenMinutes, .fifteenMinutes, .thirtyMinutes,
            .oneHour, .twoHours, .oneDay, .twoDays, .oneWeek, .timeToLeave,
        ]
    }

    static func matchesKnownPreset(_ alert: CalendarEventAlert, isAllDay: Bool) -> Bool {
        options(isAllDay: isAllDay).contains { preset in
            if preset == .timeToLeave {
                return alert.timingKind == .timeToLeave
            }
            return alert.timingKind == .relative
                && alert.relativeOffsetSeconds == preset.relativeOffsetSeconds
        }
    }

    func apply(to alert: inout CalendarEventAlert) {
        if self == .timeToLeave {
            alert.timingKind = .timeToLeave
            return
        }
        alert.timingKind = .relative
        alert.relativeOffsetSeconds = relativeOffsetSeconds
    }

    private var relativeOffsetSeconds: Int {
        switch self {
        case .atTime: return 0
        case .fiveMinutes: return -5 * 60
        case .tenMinutes: return -10 * 60
        case .fifteenMinutes: return -15 * 60
        case .thirtyMinutes: return -30 * 60
        case .oneHour: return -60 * 60
        case .twoHours: return -2 * 60 * 60
        case .oneDay: return -24 * 60 * 60
        case .twoDays: return -2 * 24 * 60 * 60
        case .oneWeek: return -7 * 24 * 60 * 60
        case .timeToLeave: return 0
        case .allDaySameDay: return 9 * 60 * 60
        case .allDayOneDay: return -15 * 60 * 60
        case .allDayTwoDays: return -39 * 60 * 60
        case .allDayOneWeek: return -159 * 60 * 60
        }
    }
}

enum SettingsCalendarAlertUnit: String, CaseIterable, Identifiable {
    case minutes
    case hours
    case days
    case weeks

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var seconds: Int {
        switch self {
        case .minutes: return 60
        case .hours: return 60 * 60
        case .days: return 24 * 60 * 60
        case .weeks: return 7 * 24 * 60 * 60
        }
    }

    static func inferred(from offsetSeconds: Int) -> SettingsCalendarAlertUnit {
        let absoluteSeconds = abs(offsetSeconds)
        if absoluteSeconds > 0, absoluteSeconds % SettingsCalendarAlertUnit.weeks.seconds == 0 {
            return .weeks
        }
        if absoluteSeconds > 0, absoluteSeconds % SettingsCalendarAlertUnit.days.seconds == 0 {
            return .days
        }
        if absoluteSeconds > 0, absoluteSeconds % SettingsCalendarAlertUnit.hours.seconds == 0 {
            return .hours
        }
        return .minutes
    }
}

enum SettingsCalendarAlertRelation: String, CaseIterable, Identifiable {
    case before
    case after

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}
