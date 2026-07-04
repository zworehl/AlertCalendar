import Foundation

extension MenuContentView {
    var displayReferenceDate: Date {
        dropdownReferenceDate
    }

    func prepareDropdownPresentation() {
        dropdownReferenceDate = AlertCalendarClock.nowRoundedToSecond()
        splitUpcomingPanelHeight = 0
    }
}
