import AppKit
import EventKit
import Foundation

extension CalendarMonitor {
    func refreshUpcomingItems(reason: CalendarMonitorRefreshReason = .manual) async {
        await enqueueRefreshAndWait(reason: reason)
    }

    func refreshUpcomingItemsImpl(
        reason: CalendarMonitorRefreshReason
    ) async -> CalendarMonitorRefreshExecutionReport {
        await refreshUpcomingItemsImpl(reasons: [reason])
    }

    func refreshUpcomingItemsImpl(
        reasons: Set<CalendarMonitorRefreshReason>
    ) async -> CalendarMonitorRefreshExecutionReport {
        var report = CalendarMonitorRefreshExecutionReport()
        let plan = CalendarMonitorRefreshPlan(reasons: reasons)
        let reason = plan.primaryReason
        if plan.refreshesCalendarSnapshot {
            refreshAvailableCalendars()
        }
        let storedSettings = settingsStore.load()
        if storedSettings != currentSettings {
            reloadCurrentSettings(storedSettings)
        }
        let now = fixedSecondNow()
        let settings = snapshotSettings()
        if plan.includesEventStoreChange {
            refreshManagedFootballTrackingSnapshot(now: now)
            refreshGameSaleTrackingSnapshot(now: now)
        }
        if !plan.refreshesCalendarStateOnly {
            let forceExternalRefresh = plan.forcesExternalFeedRefresh
            async let footballDuration = measureRefreshPhase(
                enabled: plan.triggersManagedFootballSync || plan.triggersFootballAutoAddSync
            ) {
                await self.refreshFootballDataIfNeeded(
                    now: now,
                    force: forceExternalRefresh,
                    reason: reason,
                    syncManagedEvents: plan.triggersManagedFootballSync,
                    syncAutoAdd: plan.triggersFootballAutoAddSync
                )
            }
            async let gameSalesDuration = measureRefreshPhase(enabled: plan.evaluatesGameSales) {
                await self.refreshGameSales(
                    forceRefresh: forceExternalRefresh,
                    refreshCalendarState: plan.includesEventStoreChange
                )
            }
            async let holidaysDuration = measureRefreshPhase(enabled: plan.evaluatesGoogleHolidays) {
                await self.refreshGoogleHolidays(forceRefresh: forceExternalRefresh)
            }
            let externalDurations = await (footballDuration, gameSalesDuration, holidaysDuration)
            if let duration = externalDurations.0 { report.phaseDurations["Football"] = duration }
            if let duration = externalDurations.1 { report.phaseDurations["Game Sales"] = duration }
            if let duration = externalDurations.2 { report.phaseDurations["Holidays"] = duration }

            if plan.refreshesCalendarSnapshot {
                let alertsStartedAt = Date()
                applyCalendarAlertRules(now: now, settings: settings, reason: reason)
                report.phaseDurations["Alert rules"] = Date().timeIntervalSince(alertsStartedAt)
            }
        }

        guard plan.refreshesCalendarSnapshot else {
            lastRefreshDate = fixedSecondNow()
            evaluateAlert(now: now, settings: settings)
            updateMenuBarState(now: now, settings: settings)
            rescheduleHeartbeat()
            externalFeedDiagnostics = await ExternalFeedMetrics.shared.snapshot()
            return report
        }

        let calendarStartedAt = Date()
        let fetchedLookAheadHours = max(
            settings.lookAheadHours,
            Int(ceil(Double(settings.menuBarRotationWindowMinutes) / 60.0))
        )
        let endDate = now.addingTimeInterval(Double(fetchedLookAheadHours) * 3600)

        var timedCollected: [UpcomingItem] = []
        var allDayCollected: [UpcomingItem] = []

        if hasEventsAccess, (settings.includeEvents || settings.includeAllDayEvents) {
            let selectedCalendars = calendarsForSelection(
                kind: .event,
                selectedIDs: settings.selectedEventCalendarIDs
            )
            let lookBackHours = max(24, fetchedLookAheadHours)
            let eventsStart = now.addingTimeInterval(-Double(lookBackHours) * 3600)
            let events = loadEvents(from: eventsStart, to: endDate, now: now, calendars: selectedCalendars)
            if settings.includeEvents {
                timedCollected.append(contentsOf: events.timedItems)
            }
            allDayCollected = settings.includeAllDayEvents ? events.allDayItems : []
        }

        if settings.includeReminders, hasRemindersAccess {
            let selectedCalendars = calendarsForSelection(
                kind: .reminder,
                selectedIDs: settings.selectedReminderCalendarIDs
            )
            timedCollected.append(contentsOf: cachedReminderItems(to: endDate, calendars: selectedCalendars))
            if plan.schedulesReminderFetch {
                scheduleReminderRefresh(to: endDate, calendars: selectedCalendars)
            }
        } else {
            cancelReminderRefresh(clearCachedItems: true)
        }

        if settings.includesAnyAstronomy {
            timedCollected.append(contentsOf: loadAstronomyItems(from: now, to: endDate, settings: settings))
        }

        timedCollected.sort { UpcomingItem.sortPrecedes($0, $1) }
        allDayCollected.sort { UpcomingItem.sortPrecedes($0, $1) }
        let deduplicatedTimedItems = deduplicatedItemsByNotificationKey(timedCollected)
        let deduplicatedAllDayItems = deduplicatedItemsByNotificationKey(allDayCollected)

        pruneSkippedKeys(using: deduplicatedTimedItems, allDayItems: deduplicatedAllDayItems)

        let visibleTimedItems = deduplicatedTimedItems.filter { !skippedItemKeys.contains($0.notificationKey) }
        let visibleAllDayItems = deduplicatedAllDayItems.filter { !skippedItemKeys.contains($0.notificationKey) }

        if upcomingItems != visibleTimedItems {
            upcomingItems = visibleTimedItems
        }
        if allDayEventItems != visibleAllDayItems {
            allDayEventItems = visibleAllDayItems
        }
        scheduleEventTitleRewritesIfNeeded(now: now, settings: settings)
        lastRefreshDate = fixedSecondNow()
        pruneAlertCaches(using: visibleTimedItems)
        evaluateAlert(now: now, settings: settings)
        updateMenuBarState(now: now, settings: settings)
        rescheduleHeartbeat()
        requestSlackStatusSyncEvaluation(now: now, settings: settings)
        externalFeedDiagnostics = await ExternalFeedMetrics.shared.snapshot()
        report.phaseDurations["Calendar snapshot"] = Date().timeIntervalSince(calendarStartedAt)
        return report
    }

    func measureRefreshPhase(
        enabled: Bool,
        operation: @escaping @MainActor () async -> Void
    ) async -> TimeInterval? {
        guard enabled else { return nil }
        let startedAt = Date()
        await operation()
        return Date().timeIntervalSince(startedAt)
    }

    func pruneSkippedKeys(using items: [UpcomingItem], allDayItems: [UpcomingItem] = []) {
        let validKeys = Set((items + allDayItems).map(\.notificationKey))
        let previous = skippedItemKeys
        skippedItemKeys.formIntersection(validKeys)
        if skippedItemKeys != previous {
            persistSkippedItemKeys()
        }
    }

    func deduplicatedItemsByNotificationKey(_ items: [UpcomingItem]) -> [UpcomingItem] {
        var seenKeys: Set<String> = []
        var deduplicated: [UpcomingItem] = []
        deduplicated.reserveCapacity(items.count)

        for item in items {
            if seenKeys.insert(item.notificationKey).inserted {
                deduplicated.append(item)
            }
        }

        return deduplicated
    }

    func skipItem(_ item: UpcomingItem) {
        skippedItemKeys.insert(item.notificationKey)
        persistSkippedItemKeys()
        upcomingItems.removeAll { $0.notificationKey == item.notificationKey }
        allDayEventItems.removeAll { $0.notificationKey == item.notificationKey }
        if activeAlertItem?.notificationKey == item.notificationKey {
            activeAlertItem = nil
        }

        let now = fixedSecondNow()
        let settings = snapshotSettings()
        evaluateAlert(now: now, settings: settings)
        updateMenuBarState(now: now, settings: settings)
        requestSlackStatusSyncEvaluation(now: now, settings: settings)
    }

    func hasSkippedItems() -> Bool {
        !skippedItemKeys.isEmpty
    }

    func restoreSkippedItems() {
        guard !skippedItemKeys.isEmpty else { return }
        skippedItemKeys.removeAll()
        persistSkippedItemKeys()
        refreshNow(reason: .itemAction)
    }

    func persistSkippedItemKeys() {
        let newValue = Array(skippedItemKeys).sorted()
        let currentValue = (defaults.stringArray(forKey: DefaultsKeys.skippedItemKeys) ?? []).sorted()
        guard newValue != currentValue else { return }
        defaults.set(newValue, forKey: DefaultsKeys.skippedItemKeys)
    }

    func markReminderCompleted(_ item: UpcomingItem) {
        guard item.kind == .reminder else { return }
        guard hasRemindersAccess else { return }

        guard let reminder = eventStore.calendarItem(withIdentifier: item.id) as? EKReminder else {
            skipItem(item)
            return
        }

        reminder.isCompleted = true
        reminder.completionDate = fixedSecondNow()

        do {
            try eventStore.save(reminder, commit: true)
            skipItem(item)
            refreshNow(reason: .itemAction)
        } catch {
            calendarAccessDescription = "Could not mark reminder as completed."
        }
    }
}
