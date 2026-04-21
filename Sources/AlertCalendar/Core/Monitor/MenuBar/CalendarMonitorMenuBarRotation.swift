import AppKit
import EventKit
import Foundation

extension CalendarMonitor {
    nonisolated static func updatedFootballGoalHighlight(
        _ highlight: FootballGoalHighlight?,
        queueMatchIDs: Set<String>,
        selectedMatchID: String?
    ) -> FootballGoalHighlight? {
        guard var highlight else { return nil }
        guard queueMatchIDs.contains(highlight.matchID) else { return nil }

        if selectedMatchID == highlight.matchID {
            highlight.hasBeenShownInMenuBar = true
            return highlight
        }

        if highlight.hasBeenShownInMenuBar {
            return nil
        }

        return highlight
    }

    func primaryReminderItem(now: Date) -> UpcomingItem? {
        let reminders = upcomingItems.filter { $0.kind == .reminder }
        if let upcoming = reminders.first(where: { $0.date >= now }) {
            return upcoming
        }
        return reminders.last(where: { $0.date < now })
    }

    func rotatingReminderItem(now: Date, settings: AppSettings) -> UpcomingItem? {
        let futureWindowSeconds = TimeInterval(max(5, settings.menuBarRotationWindowMinutes) * 60)
        let reminders = upcomingItems.filter {
            $0.kind == .reminder
                && Self.shouldIncludeTimedItemInMenuBarRotation(
                    $0,
                    now: now,
                    futureWindowSeconds: futureWindowSeconds
                )
        }
        return rotatingTimedMenuBarItem(from: reminders, now: now, settings: settings)
    }

    func rotatingAllDayEventItem(now: Date, settings: AppSettings) -> UpcomingItem? {
        guard !allDayEventItems.isEmpty else { return nil }
        guard allDayEventItems.count > 1 else { return allDayEventItems[0] }

        let rotationSeconds = max(5, settings.concurrentEventRotationSeconds)
        let slot = rotationSlot(now: now, seconds: rotationSeconds)
        let rotatingIndex = abs(slot) % allDayEventItems.count
        return allDayEventItems[rotatingIndex]
    }

    func rotatingTimedItem(now: Date, settings: AppSettings) -> UpcomingItem? {
        let futureWindowSeconds = TimeInterval(max(5, settings.menuBarRotationWindowMinutes) * 60)
        let timedItems = upcomingItems.filter {
            $0.kind == .event
                && isTimedItemDisplayableInMenuBar($0, now: now)
                && Self.shouldIncludeTimedItemInMenuBarRotation(
                    $0,
                    now: now,
                    futureWindowSeconds: futureWindowSeconds
                )
        }
        return rotatingTimedMenuBarItem(from: timedItems, now: now, settings: settings)
    }

    func rotatingTimedMenuBarItem(
        from items: [UpcomingItem],
        now: Date,
        settings: AppSettings
    ) -> UpcomingItem? {
        guard !items.isEmpty else { return nil }

        let rotationSeconds = max(5, settings.concurrentEventRotationSeconds)
        let slot = rotationSlot(now: now, seconds: rotationSeconds)
        let rotatingIndex = abs(slot) % items.count
        return items[rotatingIndex]
    }

    nonisolated static func shouldIncludeTimedItemInMenuBarRotation(
        _ item: UpcomingItem,
        now: Date,
        futureWindowSeconds: TimeInterval
    ) -> Bool {
        guard !item.isAllDay else { return false }

        if item.kind == .reminder, item.date <= now {
            return true
        }

        if item.kind == .event,
           let endDate = item.endDate,
           item.date <= now,
           endDate > now {
            return true
        }

        return item.date >= now && item.date.timeIntervalSince(now) <= futureWindowSeconds
    }

    func rotationSlot(now: Date, seconds: Int) -> Int {
        let clamped = max(1, seconds)
        return Int(now.timeIntervalSince1970 / Double(clamped))
    }

    nonisolated static func resolvedMenuBarRotationState(
        for poolKeys: [String],
        slot: Int,
        previousState: MenuBarRotationState
    ) -> MenuBarRotationState {
        guard !poolKeys.isEmpty else {
            return MenuBarRotationState()
        }

        let defaultIndex = abs(slot) % poolKeys.count
        let isSameSlot = previousState.slot == slot

        if isSameSlot {
            if let selectedKey = previousState.selectedKey,
               let currentIndex = poolKeys.firstIndex(of: selectedKey) {
                return MenuBarRotationState(slot: slot, selectedKey: selectedKey, selectedIndex: currentIndex)
            }

            if let previousIndex = previousState.selectedIndex,
               poolKeys.indices.contains(previousIndex) {
                let selectedKey = poolKeys[previousIndex]
                return MenuBarRotationState(slot: slot, selectedKey: selectedKey, selectedIndex: previousIndex)
            }

            let selectedKey = poolKeys[defaultIndex]
            return MenuBarRotationState(slot: slot, selectedKey: selectedKey, selectedIndex: defaultIndex)
        }

        if let selectedKey = previousState.selectedKey,
           let currentIndex = poolKeys.firstIndex(of: selectedKey) {
            let nextIndex = (currentIndex + 1) % poolKeys.count
            let nextKey = poolKeys[nextIndex]
            return MenuBarRotationState(slot: slot, selectedKey: nextKey, selectedIndex: nextIndex)
        }

        if let previousIndex = previousState.selectedIndex {
            let nextIndex = ((previousIndex % poolKeys.count) + 1) % poolKeys.count
            let nextKey = poolKeys[nextIndex]
            return MenuBarRotationState(slot: slot, selectedKey: nextKey, selectedIndex: nextIndex)
        }

        let selectedKey = poolKeys[defaultIndex]
        return MenuBarRotationState(slot: slot, selectedKey: selectedKey, selectedIndex: defaultIndex)
    }

    nonisolated static func resolvedMenuBarRotationState(
        for queueKeys: [String],
        now: Date,
        rotationInterval: TimeInterval,
        previousState: MenuBarRotationState,
        allowMissingSelectedKeyHold: Bool
    ) -> MenuBarRotationState {
        guard !queueKeys.isEmpty || (allowMissingSelectedKeyHold && previousState.selectedKey != nil) else {
            return MenuBarRotationState()
        }

        let normalizedInterval = max(1, rotationInterval)
        let shouldKeepCurrentSelection = previousState.selectedKey != nil
            && previousState.startedAt.map { now.timeIntervalSince($0) < normalizedInterval } == true

        if shouldKeepCurrentSelection {
            if let selectedKey = previousState.selectedKey,
               let currentIndex = queueKeys.firstIndex(of: selectedKey) {
                return MenuBarRotationState(
                    slot: previousState.slot ?? 0,
                    selectedKey: selectedKey,
                    selectedIndex: currentIndex,
                    startedAt: previousState.startedAt
                )
            }

            if allowMissingSelectedKeyHold,
               let selectedKey = previousState.selectedKey {
                return MenuBarRotationState(
                    slot: previousState.slot ?? 0,
                    selectedKey: selectedKey,
                    selectedIndex: previousState.selectedIndex,
                    startedAt: previousState.startedAt
                )
            }

            if !queueKeys.isEmpty {
                let preservedIndex = min(max(previousState.selectedIndex ?? 0, 0), queueKeys.count - 1)
                return MenuBarRotationState(
                    slot: previousState.slot ?? 0,
                    selectedKey: queueKeys[preservedIndex],
                    selectedIndex: preservedIndex,
                    startedAt: previousState.startedAt
                )
            }
        }

        guard !queueKeys.isEmpty else {
            return MenuBarRotationState()
        }

        let nextIndex: Int
        if let selectedKey = previousState.selectedKey,
           let currentIndex = queueKeys.firstIndex(of: selectedKey) {
            nextIndex = queueKeys.count == 1 ? 0 : (currentIndex + 1) % queueKeys.count
        } else if let previousIndex = previousState.selectedIndex {
            let normalizedPreviousIndex = min(max(previousIndex, -1), queueKeys.count - 1)
            nextIndex = queueKeys.count == 1 ? 0 : (normalizedPreviousIndex + 1 + queueKeys.count) % queueKeys.count
        } else {
            nextIndex = 0
        }

        return MenuBarRotationState(
            slot: (previousState.slot ?? -1) + 1,
            selectedKey: queueKeys[nextIndex],
            selectedIndex: nextIndex,
            startedAt: now
        )
    }

    nonisolated static func preservedMenuBarSelectionKeyIfNeeded(
        slot: Int,
        previousState: MenuBarRotationState,
        queueKeys: [String],
        preferredPoolKeys: [String],
        allowMissingSelectedKeyHold: Bool
    ) -> String? {
        guard previousState.slot == slot,
              let selectedKey = previousState.selectedKey
        else {
            return nil
        }

        guard !preferredPoolKeys.contains(selectedKey) else {
            return nil
        }

        if queueKeys.contains(selectedKey) {
            return selectedKey
        }

        return allowMissingSelectedKeyHold ? selectedKey : nil
    }

    nonisolated static func shouldHoldElapsedPointInTimeMenuBarItem(_ item: UpcomingItem, now: Date) -> Bool {
        guard item.kind == .event,
              !item.isAllDay,
              item.endDate == nil,
              item.date <= now
        else {
            return false
        }

        return true
    }


}
