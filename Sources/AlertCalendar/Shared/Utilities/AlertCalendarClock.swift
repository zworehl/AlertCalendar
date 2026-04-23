import Foundation

enum AlertCalendarClock {
    static func nowRoundedToSecond() -> Date {
        roundedDownToSecond(Date())
    }

    static func roundedDownToSecond(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
    }
}
