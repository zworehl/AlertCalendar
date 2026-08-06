import EventKit
import Foundation

extension CalendarMonitor {
    func writableGoogleHolidayTargetCalendars() -> [AvailableCalendar] {
        googleHolidayTargetCalendars().map { calendar in
            AvailableCalendar(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                color: color(from: calendar),
                kind: .event,
                accountTitle: normalizedAccountTitle(for: calendar),
                isSubscribed: false
            )
        }
    }

    func googleHolidayTargetCalendars() -> [EKCalendar] {
        eventStore.calendars(for: .event)
            .filter { calendar in
                calendar.type != .subscription
                    && calendar.type != .birthday
                    && calendar.allowsContentModifications
            }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    func resolvedGoogleHolidayTargetCalendar(settings: AppSettings? = nil) -> EKCalendar? {
        let selectedID = (settings ?? snapshotSettings()).googleHolidayTargetCalendarID
        guard !selectedID.isEmpty else { return nil }
        return googleHolidayTargetCalendars().first { $0.calendarIdentifier == selectedID }
    }

    func ensureGoogleHolidayTargetCalendarIsSelected(_ calendarIdentifier: String) {
        var selectedIDs = selectedCalendarIDs(for: .event)
        guard selectedIDs.insert(calendarIdentifier).inserted else { return }
        defaults.set(Array(selectedIDs).sorted(), forKey: DefaultsKeys.selectedEventCalendarIDs)
    }
}
