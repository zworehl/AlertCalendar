import EventKit
import Foundation

extension CalendarMonitor {
    func managedGoogleHolidayID(
        for event: EKEvent,
        records: [ManagedGoogleHolidayEventRecord],
        calendar: Calendar
    ) -> String? {
        if let record = Self.managedGoogleHolidayRecord(
            eventIdentifier: event.eventIdentifier,
            eventUID: normalizedEventUID(for: event),
            calendarIdentifier: event.calendar?.calendarIdentifier,
            title: event.title,
            startDate: event.startDate,
            isAllDay: event.isAllDay,
            records: records,
            calendar: calendar
        ) {
            return record.holiday.id
        }

        return managedGoogleHolidayID(from: event.notes)
    }

    nonisolated static func managedGoogleHolidayRecord(
        eventIdentifier: String?,
        eventUID: String?,
        calendarIdentifier: String?,
        title: String?,
        startDate: Date?,
        isAllDay: Bool,
        records: [ManagedGoogleHolidayEventRecord],
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> ManagedGoogleHolidayEventRecord? {
        if let eventIdentifier = AlertCalendarString.trimmedNonEmpty(eventIdentifier),
           let record = records.first(where: {
               AlertCalendarString.trimmedNonEmpty($0.eventIdentifier) == eventIdentifier
           }) {
            return record
        }

        if let eventUID = AlertCalendarString.trimmedNonEmpty(eventUID),
           let record = records.first(where: {
               AlertCalendarString.trimmedNonEmpty($0.eventUID) == eventUID
           }) {
            return record
        }

        guard isAllDay,
              let calendarIdentifier,
              let title,
              let startDate else {
            return nil
        }

        let semanticID = GoogleHolidayMerger.semanticKey(
            title: title,
            startDate: startDate,
            calendar: calendar
        )
        return records.first { record in
            record.calendarIdentifier == calendarIdentifier
                && calendar.isDate(record.holiday.startDate, inSameDayAs: startDate)
                && record.holiday.id == semanticID
        }
    }

    nonisolated static func googleHolidayEventNeedsMetadataCleanup(
        notes: String?,
        url: URL?
    ) -> Bool {
        notes != nil || url != nil
    }

    private func managedGoogleHolidayID(from notes: String?) -> String? {
        guard Self.isManagedGoogleHolidayNotes(notes) else { return nil }
        return notes?
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("Holiday key: ") })
            .map { String($0.dropFirst("Holiday key: ".count)) }
    }

    nonisolated static func isManagedGoogleHolidayNotes(_ notes: String?) -> Bool {
        guard let notes else { return false }
        return notes.contains(googleHolidayManagedMarker)
            || legacyGoogleHolidayManagedMarkers.contains(where: notes.contains)
    }
}
