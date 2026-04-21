import AppKit
import EventKit
import Foundation

extension CalendarMonitor {
    func menuLabel(
        for item: UpcomingItem?,
        now: Date,
        simplified: Bool,
        activeEventDisplayMode: ActiveEventDisplayMode,
        useEventTitleEllipsis: Bool,
        eventTitleMaxCharacters: Int,
        fallback: String
    ) -> String {
        guard let item else { return fallback }
        return menuSegment(
            for: item,
            now: now,
            simplified: simplified,
            activeEventDisplayMode: activeEventDisplayMode,
            useEventTitleEllipsis: useEventTitleEllipsis,
            eventTitleMaxCharacters: eventTitleMaxCharacters
        )
    }

    func menuSegment(
        for item: UpcomingItem,
        now: Date,
        simplified: Bool,
        activeEventDisplayMode: ActiveEventDisplayMode,
        useEventTitleEllipsis: Bool,
        eventTitleMaxCharacters: Int
    ) -> String {
        let baseTitle = item.footballMatch.map(FootballFixtureFormatter.calendarTitle(for:)) ?? item.title
        let compactTitle: String
        if useEventTitleEllipsis {
            compactTitle = trimmedTitle(baseTitle, maxLength: max(1, eventTitleMaxCharacters))
        } else {
            compactTitle = baseTitle
        }

        if let footballMatch = item.footballMatch,
           footballMatch.statusState != .scheduled || item.date <= now {
            return compactTitle
        }

        if item.kind == .event,
           item.date <= now,
           (item.endDate ?? item.date) > now,
           FootballFixtureFormatter.looksLikeFootballCalendarTitle(item.title) {
            return compactTitle
        }

        if item.kind == .event,
           item.endDate == nil,
           item.date <= now {
            return compactTitle
        }
        if item.isAllDay {
            if isBirthdayItem(item) {
                return compactTitle
            }
            let allDayDetail = allDayLabel(for: item) ?? "all-day"
            return "\(compactTitle) \(allDayDetail)"
        }
        if item.kind == .reminder, item.date <= now {
            return "\(compactTitle) \(elapsedCountdown(from: item.date, to: now, simplified: simplified)) ago"
        }
        if item.kind == .event, let endDate = item.endDate, item.date <= now, endDate > now {
            switch activeEventDisplayMode {
            case .remaining:
                return "\(compactTitle) \(relativeCountdown(to: endDate, from: now, simplified: simplified)) left"
            case .elapsed:
                return "\(compactTitle) started \(elapsedCountdown(from: item.date, to: now, simplified: simplified)) ago"
            }
        }
        return "\(compactTitle) in \(relativeCountdown(to: item.date, from: now, simplified: simplified))"
    }

    func footballMenuBarTrailingText(
        for item: UpcomingItem,
        now: Date,
        simplified: Bool
    ) -> String? {
        guard let footballMatch = item.footballMatch else { return nil }
        let aggregateText = FootballFixtureFormatter.menuBarAggregateText(for: footballMatch)

        if footballMatch.statusState == .scheduled, item.date > now {
            let countdownText = "in \(relativeCountdown(to: item.date, from: now, simplified: simplified))"
            if let aggregateText, !aggregateText.isEmpty {
                return "\(aggregateText) \(countdownText)"
            }
            return countdownText
        }

        return aggregateText
    }

    func footballMenuBarStatusText(
        for item: UpcomingItem,
        now: Date
    ) -> String? {
        guard let footballMatch = item.footballMatch else { return nil }
        guard let badgeText = Self.footballStatusBadgeText(for: footballMatch, now: now) else { return nil }

        if footballMatch.statusState != .scheduled || footballMatch.statusReliability != .reported {
            return badgeText
        }

        return nil
    }

    func isBirthdayItem(_ item: UpcomingItem) -> Bool {
        guard item.kind == .event, let calendarID = item.calendarID else { return false }
        return birthdayCalendarIDs.contains(calendarID)
    }

    func displayedItemsForMenuBar(now: Date, settings: AppSettings) -> [UpcomingItem] {
        let queue = unifiedMenuBarQueue(now: now, settings: settings)
        guard !queue.isEmpty else {
            menuBarRotationState = MenuBarRotationState()
            return []
        }

        let previousState = menuBarRotationState
        let allCandidates = allMenuBarCandidateItems()
        let fallbackHeldItem = previousState.selectedKey.flatMap { selectedKey in
            allCandidates.first(where: { $0.notificationKey == selectedKey })
        }
        let allowMissingSelectedKeyHold = fallbackHeldItem.map {
            Self.shouldHoldElapsedPointInTimeMenuBarItem($0, now: now)
        } ?? false

        menuBarRotationState = Self.resolvedMenuBarRotationState(
            for: queue.map(\.notificationKey),
            now: now,
            rotationInterval: TimeInterval(max(5, settings.concurrentEventRotationSeconds)),
            previousState: previousState,
            allowMissingSelectedKeyHold: allowMissingSelectedKeyHold
        )

        if let selectedKey = menuBarRotationState.selectedKey,
           let selectedItem = queue.first(where: { $0.notificationKey == selectedKey })
            ?? fallbackHeldItem.flatMap({ $0.notificationKey == selectedKey ? $0 : nil }) {
            return [selectedItem]
        }

        let fallbackIndex = min(max(menuBarRotationState.selectedIndex ?? 0, 0), queue.count - 1)
        return [queue[fallbackIndex]]
    }


}
