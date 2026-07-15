import EventKit
import Foundation

extension CalendarMonitor {
    func gameSaleCalendarAlertOption() -> GameSaleCalendarAlertOption {
        GameSaleCalendarAlertOption(
            rawValue: defaults.string(forKey: DefaultsKeys.gameSaleCalendarAlertOption) ?? ""
        ) ?? .fifteenMinutesBefore
    }

    func applyGameSaleAlertConfiguration(to event: EKEvent) {
        if let relativeOffset = gameSaleCalendarAlertOption().relativeOffset() {
            event.alarms = [EKAlarm(relativeOffset: relativeOffset)]
        } else {
            event.alarms = nil
        }
    }

    func applyManagedGameSaleAlertConfiguration() {
        guard hasEventsAccess else { return }
        var updatedRecords: [ManagedGameSaleEventRecord] = []

        for record in managedGameSaleEventRecords {
            guard let event = resolveManagedGameSaleEvent(for: record) else { continue }
            let previousAlarms = event.alarms ?? []
            applyGameSaleAlertConfiguration(to: event)
            guard event.alarms != previousAlarms else { continue }

            do {
                try eventStore.save(event, span: .thisEvent, commit: false)
                updatedRecords.append(
                    ManagedGameSaleEventRecord(
                        sale: record.sale,
                        calendarIdentifier: event.calendar?.calendarIdentifier ?? record.calendarIdentifier,
                        eventIdentifier: event.eventIdentifier,
                        eventUID: normalizedEventUID(for: event)
                    )
                )
            } catch {
                continue
            }
        }

        guard !updatedRecords.isEmpty else { return }
        try? eventStore.commit()
        let updatedByID = Dictionary(uniqueKeysWithValues: updatedRecords.map { ($0.saleID, $0) })
        persistManagedGameSaleEventRecords(
            managedGameSaleEventRecords.map { updatedByID[$0.saleID] ?? $0 }
        )
    }
}
