import AppKit
import EventKit
import Foundation

extension CalendarMonitor {
    func refreshUpcomingItems(reason: CalendarMonitorRefreshReason = .manual) async {
        await enqueueRefreshAndWait(reason: reason)
    }

    func refreshUpcomingItemsImpl(reason: CalendarMonitorRefreshReason) async {
        refreshAvailableCalendars()
        let now = fixedSecondNow()
        let settings = pruneNonWorkingDateKeysIfNeeded(now: now, settings: snapshotSettings())
        let forceExternalRefresh = reason.forcesExternalFeedRefresh
        await refreshFootballDataIfNeeded(
            now: now,
            force: forceExternalRefresh,
            reason: reason
        )
        await refreshGameSales(
            forceRefresh: forceExternalRefresh,
            refreshCalendarState: reason == .eventStoreChanged
        )
        await refreshGoogleHolidays(forceRefresh: forceExternalRefresh)
        if reason != .footballHeartbeat {
            applyCalendarAlertRules(now: now, settings: settings, reason: reason)
        }
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
                selectedIDs: settings.selectedEventCalendarIDs,
                weekdayOnlyIDs: settings.weekdayOnlyEventCalendarIDs,
                nonWorkingDateKeys: settings.nonWorkingDateKeys,
                now: now
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
                selectedIDs: settings.selectedReminderCalendarIDs,
                weekdayOnlyIDs: settings.weekdayOnlyReminderCalendarIDs,
                nonWorkingDateKeys: settings.nonWorkingDateKeys,
                now: now
            )
            let reminders = await loadReminders(from: nil, to: endDate, calendars: selectedCalendars)
            timedCollected.append(contentsOf: reminders)
        }

        if settings.includesAnyAstronomy {
            timedCollected.append(contentsOf: loadAstronomyItems(from: now, to: endDate, settings: settings))
        }

        timedCollected.sort { $0.date < $1.date }
        allDayCollected.sort { $0.date < $1.date }
        let deduplicatedTimedItems = deduplicatedItemsByNotificationKey(timedCollected)
        let deduplicatedAllDayItems = deduplicatedItemsByNotificationKey(allDayCollected)

        pruneSkippedKeys(using: deduplicatedTimedItems, allDayItems: deduplicatedAllDayItems)

        let visibleTimedItems = deduplicatedTimedItems.filter { !skippedItemKeys.contains($0.notificationKey) }
        let visibleAllDayItems = deduplicatedAllDayItems.filter { !skippedItemKeys.contains($0.notificationKey) }

        upcomingItems = visibleTimedItems
        allDayEventItems = visibleAllDayItems
        if isInitialLoadInProgress {
            isInitialLoadInProgress = false
        }
        lastRefreshDate = now
        pruneAlertCaches(using: visibleTimedItems)
        evaluateAlert(now: now, settings: settings)
        updateMenuBarState(now: now, settings: settings)
        requestSlackStatusSyncEvaluation(now: now, settings: settings)
        externalFeedDiagnostics = await ExternalFeedMetrics.shared.snapshot()
    }

    func pruneSkippedKeys(using items: [UpcomingItem], allDayItems: [UpcomingItem] = []) {
        let validKeys = Set((items + allDayItems).map(\.notificationKey))
        let previous = skippedItemKeys
        skippedItemKeys.formIntersection(validKeys)
        if skippedItemKeys != previous {
            persistSkippedItemKeys()
        }
    }

    func pruneNonWorkingDateKeysIfNeeded(now: Date, settings: AppSettings) -> AppSettings {
        let normalized = WorkingDayRules.normalizedNonWorkingDateKeys(settings.nonWorkingDateKeys, now: now)
        guard normalized != settings.nonWorkingDateKeys else { return settings }

        defaults.set(Array(normalized).sorted(), forKey: DefaultsKeys.nonWorkingDateKeys)
        reloadCurrentSettings()
        return snapshotSettings()
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
