import EventKit
import Foundation

extension CalendarMonitor {
    func refreshGameSales(forceRefresh: Bool = false) async {
        guard !isRefreshingGameSales else { return }
        isRefreshingGameSales = true
        defer { isRefreshingGameSales = false }

        let now = fixedSecondNow()
        cleanupEndedGameSales(now: now)

        do {
            let fetched = try await gameSalesClient.fetchScheduledSales(
                now: now,
                forceRefresh: forceRefresh
            )
            fetchedGameSales = fetched
            gameSalesErrorDescription = nil
        } catch {
            gameSalesErrorDescription = error.localizedDescription
        }

        reconcileManagedGameSalesWithFetchedSchedule()
        refreshGameSaleTrackingSnapshot(now: now)
        await autoAddGameSalesIfNeeded(now: now)
        refreshGameSaleTrackingSnapshot(now: now)
    }

    func reconcileManagedGameSalesWithFetchedSchedule() {
        let fetchedByID = Dictionary(uniqueKeysWithValues: fetchedGameSales.map { ($0.id, $0) })
        let targetCalendar = resolvedGameSaleTargetCalendar()
        var nextRecords: [ManagedGameSaleEventRecord] = []
        var needsCommit = false

        for record in managedGameSaleEventRecords {
            guard let event = resolveManagedGameSaleEvent(for: record),
                  let currentCalendar = event.calendar else {
                nextRecords.append(record)
                continue
            }
            let desiredSale = fetchedByID[record.saleID] ?? record.sale
            let desiredCalendar = targetCalendar ?? currentCalendar
            let needsUpdate = desiredSale != record.sale
                || desiredCalendar.calendarIdentifier != currentCalendar.calendarIdentifier
            guard needsUpdate else {
                nextRecords.append(record)
                continue
            }

            applyGameSale(desiredSale, to: event, calendar: desiredCalendar)
            do {
                try eventStore.save(event, span: .thisEvent, commit: false)
                nextRecords.append(
                    ManagedGameSaleEventRecord(
                        sale: desiredSale,
                        calendarIdentifier: desiredCalendar.calendarIdentifier,
                        eventIdentifier: event.eventIdentifier,
                        eventUID: normalizedEventUID(for: event)
                    )
                )
                needsCommit = true
            } catch {
                nextRecords.append(record)
            }
        }

        if needsCommit {
            do {
                try eventStore.commit()
            } catch {
                return
            }
        }
        persistManagedGameSaleEventRecords(nextRecords)
    }

    func cleanupEndedGameSales(now: Date) {
        guard hasEventsAccess else { return }
        let removeExternal = defaults.bool(forKey: DefaultsKeys.removeEndedGameSalesAutomatically)
            && resolvedGameSaleTargetCalendar().map {
                Self.isDedicatedGameSalesCalendarTitle($0.title)
            } == true
        let calendarSnapshots = gameSaleCalendarSnapshots(now: now)
        var eventIdentifiersToRemove: Set<String> = []
        var recordsToKeep: [ManagedGameSaleEventRecord] = []
        var needsCommit = false

        for record in managedGameSaleEventRecords {
            guard let event = resolveManagedGameSaleEvent(for: record) else {
                if record.sale.endDateExclusive > now {
                    addDismissedGameSaleID(record.saleID)
                }
                continue
            }

            if record.sale.endDateExclusive <= now {
                do {
                    try eventStore.remove(event, span: .thisEvent, commit: false)
                    if let identifier = event.eventIdentifier {
                        eventIdentifiersToRemove.insert(identifier)
                    }
                    needsCommit = true
                } catch {
                    recordsToKeep.append(record)
                }
            } else {
                recordsToKeep.append(record)
            }
        }

        if removeExternal {
            for snapshot in calendarSnapshots where snapshot.sale.endDateExclusive <= now {
                if let identifier = snapshot.event.eventIdentifier,
                   eventIdentifiersToRemove.contains(identifier) {
                    continue
                }
                do {
                    try eventStore.remove(snapshot.event, span: .thisEvent, commit: false)
                    needsCommit = true
                } catch {
                    continue
                }
            }
        }

        if needsCommit {
            do {
                try eventStore.commit()
            } catch {
                return
            }
        }
        persistManagedGameSaleEventRecords(recordsToKeep)
    }

    func gameSaleAutoAddStores() -> Set<GameStore> {
        let stored = defaults.stringArray(forKey: DefaultsKeys.gameSaleAutoAddStoreIDs) ?? []
        return Set(stored.compactMap(GameStore.init(rawValue:)))
    }

    func setGameSaleAutoAddEnabled(_ isEnabled: Bool, for store: GameStore) {
        var stores = gameSaleAutoAddStores()
        if isEnabled {
            stores.insert(store)
        } else {
            stores.remove(store)
        }
        defaults.set(stores.map(\.rawValue).sorted(), forKey: DefaultsKeys.gameSaleAutoAddStoreIDs)
        if isEnabled {
            Task { await refreshGameSales(forceRefresh: true) }
        }
    }

    func autoAddGameSalesIfNeeded(now: Date) async {
        guard hasEventsAccess, resolvedGameSaleTargetCalendar() != nil else { return }
        let enabledStores = gameSaleAutoAddStores()
        guard !enabledStores.isEmpty else { return }
        let dismissedIDs = dismissedGameSaleIDs()
        let existingSnapshots = gameSaleCalendarSnapshots(now: now)
        var addedSales: [GameSaleEvent] = []

        for sale in fetchedGameSales where sale.endDateExclusive > now {
            guard enabledStores.contains(sale.store),
                  !dismissedIDs.contains(sale.id) else {
                continue
            }

            if let existingSnapshot = existingSnapshots.first(where: {
                Self.gameSalesSemanticallyMatch($0.sale, sale)
            }) {
                if managedGameSaleRecord(for: sale) == nil {
                    upsertManagedGameSaleEventRecord(for: existingSnapshot.event, sale: sale)
                }
                continue
            }
            guard !isGameSalePresent(sale) else { continue }

            let didAdd = await addGameSaleToCalendar(sale)
            if didAdd {
                addedSales.append(sale)
            }
        }

        queueGameSaleAutoAddNotification(for: addedSales, now: now)
    }
}
