import EventKit
import Foundation

extension CalendarMonitor {
    func writableGameSaleTargetCalendars() -> [AvailableCalendar] {
        gameSaleTargetCalendars().map { calendar in
            AvailableCalendar(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                color: color(from: calendar),
                kind: .event,
                accountTitle: normalizedAccountTitle(for: calendar),
                isSubscribed: calendar.type == .subscription
            )
        }
    }

    func gameSaleTargetCalendarID() -> String? {
        resolvedGameSaleTargetCalendar()?.calendarIdentifier
    }

    func gameSaleTargetCalendars() -> [EKCalendar] {
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

    func resolvedGameSaleTargetCalendar() -> EKCalendar? {
        let writableCalendars = gameSaleTargetCalendars()
        guard !writableCalendars.isEmpty else {
            defaults.removeObject(forKey: DefaultsKeys.gameSaleTargetCalendarID)
            return nil
        }

        if let storedID = defaults.string(forKey: DefaultsKeys.gameSaleTargetCalendarID),
           let stored = writableCalendars.first(where: { $0.calendarIdentifier == storedID }) {
            ensureGameSaleTargetCalendarIsSelected(stored.calendarIdentifier)
            return stored
        }

        if let namedGameSales = writableCalendars.first(where: {
            Self.isDedicatedGameSalesCalendarTitle($0.title)
        }) {
            defaults.set(namedGameSales.calendarIdentifier, forKey: DefaultsKeys.gameSaleTargetCalendarID)
            ensureGameSaleTargetCalendarIsSelected(namedGameSales.calendarIdentifier)
            return namedGameSales
        }

        defaults.removeObject(forKey: DefaultsKeys.gameSaleTargetCalendarID)
        return nil
    }

    func ensureGameSaleTargetCalendarIsSelected(_ calendarIdentifier: String) {
        var selectedIDs = selectedCalendarIDs(for: .event)
        guard selectedIDs.insert(calendarIdentifier).inserted else { return }
        defaults.set(Array(selectedIDs).sorted(), forKey: DefaultsKeys.selectedEventCalendarIDs)
    }

    nonisolated static func isDedicatedGameSalesCalendarTitle(_ title: String) -> Bool {
        title.compare(
            "Game Sales",
            options: [.caseInsensitive, .diacriticInsensitive]
        ) == .orderedSame
    }
}
