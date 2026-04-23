import Foundation

extension MenuContentView {
    var displayReferenceDate: Date {
        AlertCalendarClock.nowRoundedToSecond()
    }
}
