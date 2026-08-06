import EventKit
import Foundation

struct ExistingGoogleHolidayEvent {
    let event: EKEvent
    let recordedHoliday: GoogleHolidayEvent?
}

extension CalendarMonitor {
    func googleHolidayMigrationCandidate(
        _ existing: ExistingGoogleHolidayEvent,
        matches desired: GoogleHolidayEvent,
        calendar: Calendar
    ) -> Bool {
        guard calendar.isDate(existing.event.startDate, inSameDayAs: desired.startDate) else {
            return false
        }

        if GoogleHolidayMerger.semanticKey(
            title: existing.event.title ?? "",
            startDate: existing.event.startDate,
            calendar: calendar
        ) == desired.id {
            return true
        }

        guard let recordedHoliday = existing.recordedHoliday else { return false }
        return !Set(recordedHoliday.sourceUIDs).isDisjoint(with: desired.sourceUIDs)
    }
}
