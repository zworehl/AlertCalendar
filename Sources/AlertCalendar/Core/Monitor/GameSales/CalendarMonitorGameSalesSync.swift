import EventKit
import Foundation

extension CalendarMonitor {
    nonisolated static func shouldRefreshGameSales(
        lastAttemptDate: Date?,
        lastAttemptFailed: Bool = false,
        now: Date,
        forceRefresh: Bool
    ) -> Bool {
        forceRefresh || CalendarMonitorTime.hasElapsed(
            since: lastAttemptDate,
            now: now,
            interval: lastAttemptFailed
                ? GameSalesFeedClient.failedRefreshRetryInterval
                : GameSalesFeedClient.monitorEvaluationInterval
        )
    }

    func refreshGameSales(
        forceRefresh: Bool = false,
        refreshCalendarState: Bool = false
    ) async {
        guard !isRefreshingGameSales else { return }

        let now = fixedSecondNow()
        guard Self.shouldRefreshGameSales(
            lastAttemptDate: lastGameSalesRefreshAttemptDate,
            lastAttemptFailed: lastGameSalesRefreshAttemptFailed,
            now: now,
            forceRefresh: forceRefresh
        ) else {
            if refreshCalendarState {
                refreshGameSaleTrackingSnapshot(now: now)
            }
            return
        }

        lastGameSalesRefreshAttemptDate = now
        isRefreshingGameSales = true
        defer { isRefreshingGameSales = false }

        let calendarSnapshots = gameSaleCalendarSnapshots(now: now)
        cleanupEndedGameSales(now: now, calendarSnapshots: calendarSnapshots)

        do {
            let fetched = try await gameSalesClient.fetchScheduledSales(
                now: now,
                forceRefresh: forceRefresh
            )
            fetchedGameSales = fetched
            gameSalesErrorDescription = nil
            lastGameSalesRefreshAttemptFailed = false
            markGameSalesRefreshed(at: now)
        } catch {
            gameSalesErrorDescription = error.localizedDescription
            lastGameSalesRefreshAttemptFailed = true
        }

        reconcileManagedGameSalesWithFetchedSchedule()
        refreshGameSaleTrackingSnapshot(now: now, calendarSnapshots: calendarSnapshots)
        await autoAddGameSalesIfNeeded(now: now, existingSnapshots: calendarSnapshots)
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
            let desiredSale = fetchedByID[record.saleID]
                ?? fetchedGameSales.first(where: {
                    Self.gameSalesCalendarAssociationMatches($0, record.sale)
                })
                ?? record.sale
            let desiredCalendar = targetCalendar ?? currentCalendar
            let currentSnapshot = gameSaleSnapshot(for: event)
            let eventMatchesSchedule = currentSnapshot.map {
                Self.gameSalesSemanticallyMatch($0.sale, desiredSale)
                    && $0.sale.title == desiredSale.title
                    && $0.sale.officialURL == desiredSale.officialURL
            } ?? false
            let needsUpdate = !eventMatchesSchedule
                || desiredCalendar.calendarIdentifier != currentCalendar.calendarIdentifier

            if needsUpdate {
                applyGameSale(desiredSale, to: event, calendar: desiredCalendar)
                do {
                    try eventStore.save(event, span: .thisEvent, commit: false)
                    needsCommit = true
                } catch {
                    nextRecords.append(record)
                    continue
                }
            }

            nextRecords.append(
                ManagedGameSaleEventRecord(
                    sale: desiredSale,
                    calendarIdentifier: desiredCalendar.calendarIdentifier,
                    eventIdentifier: event.eventIdentifier,
                    eventUID: normalizedEventUID(for: event)
                )
            )
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

    func cleanupEndedGameSales(
        now: Date,
        calendarSnapshots: [GameSaleCalendarSnapshot]? = nil
    ) {
        guard hasEventsAccess else { return }
        let removeExternal = defaults.bool(forKey: DefaultsKeys.removeEndedGameSalesAutomatically)
            && resolvedGameSaleTargetCalendar().map {
                Self.isDedicatedGameSalesCalendarTitle($0.title)
            } == true
        let calendarSnapshots = calendarSnapshots ?? gameSaleCalendarSnapshots(now: now)
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

    func autoAddGameSalesIfNeeded(
        now: Date,
        existingSnapshots: [GameSaleCalendarSnapshot]? = nil
    ) async {
        guard hasEventsAccess, resolvedGameSaleTargetCalendar() != nil else { return }
        let enabledStores = gameSaleAutoAddStores()
        guard !enabledStores.isEmpty else { return }
        let dismissedIDs = dismissedGameSaleIDs()
        let existingSnapshots = existingSnapshots ?? gameSaleCalendarSnapshots(now: now)
        var addedSales: [GameSaleEvent] = []

        for sale in fetchedGameSales where sale.endDateExclusive > now {
            guard enabledStores.contains(sale.store),
                  !dismissedIDs.contains(sale.id) else {
                continue
            }

            if let existingSnapshot = existingSnapshots.first(where: {
                Self.gameSalesCalendarAssociationMatches($0.sale, sale)
            }) {
                upsertManagedGameSaleEventRecord(for: existingSnapshot.event, sale: sale)
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
