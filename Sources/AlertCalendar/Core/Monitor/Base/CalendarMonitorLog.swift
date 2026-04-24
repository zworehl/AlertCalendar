import OSLog

enum CalendarMonitorLog {
    private static let subsystem = "AlertCalendar"

    static let refresh = Logger(subsystem: subsystem, category: "refresh")
    static let location = Logger(subsystem: subsystem, category: "location")
    static let football = Logger(subsystem: subsystem, category: "football")
    static let slack = Logger(subsystem: subsystem, category: "slack")
}
