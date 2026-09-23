import AppKit
import Foundation
import SwiftUI

extension MenuContentView {
    var displayReferenceDate: Date {
        dropdownReferenceDate
    }

    func prepareDropdownPresentation() {
        dropdownReferenceDate = AlertCalendarClock.nowRoundedToSecond()
        monitor.synchronizeCalendarStateIfNeeded()
        // Preference values can arrive before onAppear. Preserve them so this
        // presentation does not erase the split-column measurements SwiftUI just resolved.
    }

    func keepDropdownReferenceDateFresh() async {
        while !Task.isCancelled {
            let now = AlertCalendarClock.nowRoundedToSecond()
            let delay = monitor.nextPresentationRefreshInterval(now: now, settings: settings)
            do {
                try await Task.sleep(nanoseconds: CalendarMonitorTime.nanoseconds(forDelay: delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            dropdownReferenceDate = AlertCalendarClock.nowRoundedToSecond()
        }
    }
}
