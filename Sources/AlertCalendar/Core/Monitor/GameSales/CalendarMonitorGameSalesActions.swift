import EventKit
import Foundation

extension CalendarMonitor {
    @discardableResult
    func addGameSaleToCalendar(_ sale: GameSaleEvent) async -> Bool {
        guard hasEventsAccess else {
            calendarAccessDescription = "Calendar access is required to add game sales."
            return false
        }
        guard sale.endDateExclusive > fixedSecondNow() else { return false }
        guard let targetCalendar = resolvedGameSaleTargetCalendar() else {
            calendarAccessDescription = "Choose a writable event calendar before adding game sales."
            return false
        }

        let now = fixedSecondNow()
        if let existingSnapshot = gameSaleCalendarSnapshots(now: now).first(where: {
            Self.gameSalesCalendarAssociationMatches($0.sale, sale)
        }) {
            upsertManagedGameSaleEventRecord(for: existingSnapshot.event, sale: sale)
            removeDismissedGameSaleID(sale.id)
            refreshGameSaleTrackingSnapshot(now: now)
            return false
        }

        if let existingRecord = managedGameSaleEventRecords.first(where: { $0.saleID == sale.id }),
           let event = resolveManagedGameSaleEvent(for: existingRecord) {
            applyGameSale(sale, to: event, calendar: targetCalendar)
            do {
                try eventStore.save(event, span: .thisEvent, commit: true)
                upsertManagedGameSaleEventRecord(for: event, sale: sale)
                refreshGameSaleTrackingSnapshot(now: now)
                return false
            } catch {
                calendarAccessDescription = "Could not update the selected game sale."
                return false
            }
        }

        let event = EKEvent(eventStore: eventStore)
        applyGameSale(sale, to: event, calendar: targetCalendar)

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            ensureGameSaleTargetCalendarIsSelected(targetCalendar.calendarIdentifier)
            upsertManagedGameSaleEventRecord(for: event, sale: sale)
            removeDismissedGameSaleID(sale.id)
            refreshGameSaleTrackingSnapshot(now: now)
            refreshNow(reason: .itemAction)
            return true
        } catch {
            calendarAccessDescription = "Could not save the selected game sale."
            return false
        }
    }

    func removeGameSaleFromCalendar(_ sale: GameSaleEvent) {
        guard hasEventsAccess else {
            calendarAccessDescription = "Calendar access is required to remove game sales."
            return
        }
        guard let record = managedGameSaleRecord(for: sale) else {
            refreshGameSaleTrackingSnapshot(now: fixedSecondNow())
            return
        }

        if let event = resolveManagedGameSaleEvent(for: record) {
            do {
                try eventStore.remove(event, span: .thisEvent, commit: true)
            } catch {
                calendarAccessDescription = "Could not remove the selected game sale."
                return
            }
        }

        persistManagedGameSaleEventRecords(
            managedGameSaleEventRecords.filter {
                $0.saleID != record.saleID
                    && !Self.gameSalesCalendarAssociationMatches($0.sale, sale)
            }
        )
        addDismissedGameSaleID(sale.id)
        refreshGameSaleTrackingSnapshot(now: fixedSecondNow())
        refreshNow(reason: .itemAction)
    }

    func openGameSaleInCalendar(_ sale: GameSaleEvent) {
        let now = fixedSecondNow()
        let event = gameSaleCalendarSnapshots(now: now).first(where: {
            Self.gameSalesCalendarAssociationMatches($0.sale, sale)
        })?.event
            ?? managedGameSaleRecord(for: sale).flatMap(resolveManagedGameSaleEvent(for:))

        guard let event else {
            calendarAccessDescription = "Could not find the selected game sale in Calendar."
            _ = openCalendarApplication()
            return
        }

        Task { @MainActor in
            _ = openCalendarApplication()
            if revealCalendarEvent(event) { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            if revealCalendarEvent(event) { return }
            calendarAccessDescription = "Could not reveal the event directly in Calendar."
        }
    }

    func applyGameSale(_ sale: GameSaleEvent, to event: EKEvent, calendar: EKCalendar) {
        event.calendar = calendar
        event.title = sale.title
        event.startDate = sale.startDate
        event.endDate = sale.endDateExclusive
        event.isAllDay = true
        event.url = sale.officialURL
        event.notes = nil
        applyGameSaleAlertConfiguration(to: event)
    }

    func upsertManagedGameSaleEventRecord(for event: EKEvent, sale: GameSaleEvent) {
        guard let calendarIdentifier = event.calendar?.calendarIdentifier else { return }
        let record = ManagedGameSaleEventRecord(
            sale: sale,
            calendarIdentifier: calendarIdentifier,
            eventIdentifier: event.eventIdentifier,
            eventUID: normalizedEventUID(for: event)
        )
        persistManagedGameSaleEventRecords(
            managedGameSaleEventRecords.filter {
                $0.saleID != sale.id
                    && !Self.gameSalesCalendarAssociationMatches($0.sale, sale)
            } + [record]
        )
    }

    func dismissedGameSaleIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: DefaultsKeys.dismissedGameSaleEventIDs) ?? [])
    }

    func addDismissedGameSaleID(_ saleID: String) {
        var dismissed = dismissedGameSaleIDs()
        guard dismissed.insert(saleID).inserted else { return }
        defaults.set(Array(dismissed).sorted(), forKey: DefaultsKeys.dismissedGameSaleEventIDs)
    }

    func removeDismissedGameSaleID(_ saleID: String) {
        var dismissed = dismissedGameSaleIDs()
        guard dismissed.remove(saleID) != nil else { return }
        defaults.set(Array(dismissed).sorted(), forKey: DefaultsKeys.dismissedGameSaleEventIDs)
    }
}
