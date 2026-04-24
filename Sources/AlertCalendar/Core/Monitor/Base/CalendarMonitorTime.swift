import Foundation

enum CalendarMonitorTime {
    static func hasElapsed(since date: Date?, now: Date, interval: TimeInterval) -> Bool {
        guard let date else { return true }
        return now.timeIntervalSince(date) >= interval
    }

    static func nanoseconds(forDelay delay: TimeInterval) -> UInt64 {
        UInt64((max(0, delay) * 1_000_000_000).rounded(.up))
    }

    static func nanoseconds(until date: Date, now: Date, minimumDelay: TimeInterval = 0) -> UInt64 {
        nanoseconds(forDelay: max(minimumDelay, date.timeIntervalSince(now)))
    }
}
