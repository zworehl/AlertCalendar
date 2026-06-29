import Foundation

extension MenuContentView {
    var displayReferenceDate: Date {
        dropdownReferenceDate
    }

    func prepareDropdownPresentation() {
        dropdownReferenceDate = AlertCalendarClock.nowRoundedToSecond()
        splitContextualPanelHeight = 0
        splitUpcomingPanelHeight = 0
    }
}
