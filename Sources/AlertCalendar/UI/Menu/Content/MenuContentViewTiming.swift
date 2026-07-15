import Foundation

extension MenuContentView {
    var displayReferenceDate: Date {
        dropdownReferenceDate
    }

    func prepareDropdownPresentation() {
        dropdownReferenceDate = AlertCalendarClock.nowRoundedToSecond()
        // Preference values can arrive before onAppear. Preserve them so this
        // presentation does not erase the split-column measurements SwiftUI just resolved.
    }
}
