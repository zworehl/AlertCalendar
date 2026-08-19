import OSLog

enum CalendarMonitorLog {
    private static let subsystem = "AlertCalendar"

    static let refresh = Logger(subsystem: subsystem, category: "refresh")
    static let alerts = Logger(subsystem: subsystem, category: "calendar-alert-rules")
    static let location = Logger(subsystem: subsystem, category: "location")
    static let football = Logger(subsystem: subsystem, category: "football")
    static let slack = Logger(subsystem: subsystem, category: "slack")
    static let agendaSummary = Logger(subsystem: subsystem, category: "agenda-summary")
}
