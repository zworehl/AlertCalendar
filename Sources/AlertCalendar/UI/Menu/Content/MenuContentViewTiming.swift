import Foundation

extension MenuContentView {
    nonisolated static let dropdownRefreshIntervalNanoseconds: UInt64 = 1_000_000_000

    var displayReferenceDate: Date {
        dropdownReferenceDate
    }

    func prepareDropdownPresentation() {
        dropdownReferenceDate = AlertCalendarClock.nowRoundedToSecond()
        monitor.synchronizeCalendarState()
        // Preference values can arrive before onAppear. Preserve them so this
        // presentation does not erase the split-column measurements SwiftUI just resolved.
    }

    func keepDropdownReferenceDateFresh() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: Self.dropdownRefreshIntervalNanoseconds)
            guard !Task.isCancelled else { return }
            dropdownReferenceDate = AlertCalendarClock.nowRoundedToSecond()
        }
    }
}
