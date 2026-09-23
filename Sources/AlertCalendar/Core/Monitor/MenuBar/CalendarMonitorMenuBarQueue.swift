import AppKit
import EventKit
import Foundation

extension CalendarMonitor {
    func menuBarPreviewItems(now: Date, settings: AppSettings) -> [UpcomingItem] {
        Array(unifiedMenuBarQueue(now: now, settings: settings).prefix(1))
    }

    func allMenuBarCandidateItems() -> [UpcomingItem] {
        deduplicatedItemsByNotificationKey(upcomingItems + allDayEventItems)
    }

    func unifiedMenuBarQueue(now: Date, settings: AppSettings) -> [UpcomingItem] {
        let futureWindowSeconds = TimeInterval(max(5, settings.menuBarRotationWindowMinutes) * 60)
        let futureWindowEnd = now.addingTimeInterval(futureWindowSeconds)
        let timedItems = upcomingItems.filter {
            isTimedItemDisplayableInMenuBar($0, now: now)
                && Self.shouldIncludeTimedItemInMenuBarRotation(
                    $0,
                    now: now,
                    futureWindowSeconds: futureWindowSeconds
                )
        }
        let allDayItems = settings.includeAllDayEvents ? allDayEventItems.filter {
            Self.shouldIncludeAllDayItemInMenuBarRotation(
                startDate: $0.date,
                endDate: $0.endDate,
                now: now,
                futureWindowEnd: futureWindowEnd
            )
        } : []
        let merged = deduplicatedItemsByNotificationKey(timedItems + allDayItems)
        let candidates = Self.menuBarRotationCandidates(
            from: merged,
            now: now,
            focusOnActiveEvents: settings.focusMenuBarOnActiveEvents
        )

        return candidates.sorted { left, right in
            let leftPriority = menuBarQueuePriority(for: left)
            let rightPriority = menuBarQueuePriority(for: right)
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            let leftDate = Self.menuBarRotationReferenceDate(for: left, now: now)
            let rightDate = Self.menuBarRotationReferenceDate(for: right, now: now)
            if leftDate != rightDate {
                return leftDate < rightDate
            }
            if left.kind != right.kind {
                return left.kind.rawValue < right.kind.rawValue
            }
            let titleOrder = left.title.localizedCaseInsensitiveCompare(right.title)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }
            return left.notificationKey < right.notificationKey
        }
    }

    func menuBarQueuePriority(for item: UpcomingItem) -> Int {
        item.isAllDay ? 1 : 0
    }

    nonisolated static func menuBarRotationReferenceDate(for item: UpcomingItem, now: Date) -> Date {
        if let travelStartDate = travelStartDate(for: item),
           now < item.date {
            return travelStartDate
        }

        return item.date
    }

    func hasUpcomingItemsOutsideMenuBarWindow(now: Date, settings: AppSettings) -> Bool {
        let dropdownFutureWindowEnd = now.addingTimeInterval(Double(max(1, settings.lookAheadHours)) * 3600)
        let futureWindowSeconds = TimeInterval(max(5, settings.menuBarRotationWindowMinutes) * 60)
        let menuBarFutureWindowEnd = now.addingTimeInterval(futureWindowSeconds)

        let hasTimedItemsOutsideMenuBarWindow = upcomingItems.contains { item in
            isTimedItemDisplayableInMenuBar(item, now: now)
                && !Self.shouldIncludeTimedItemInMenuBarRotation(
                    item,
                    now: now,
                    futureWindowSeconds: futureWindowSeconds
                )
                && Self.shouldIncludeInDropdownPreviewWindow(
                    item,
                    now: now,
                    futureWindowEnd: dropdownFutureWindowEnd
                )
        }

        if hasTimedItemsOutsideMenuBarWindow {
            return true
        }

        return settings.includeAllDayEvents && allDayEventItems.contains { item in
            Self.shouldIncludeInDropdownPreviewWindow(
                item,
                now: now,
                futureWindowEnd: dropdownFutureWindowEnd
            ) && !Self.shouldIncludeAllDayItemInMenuBarRotation(
                startDate: item.date,
                endDate: item.endDate,
                now: now,
                futureWindowEnd: menuBarFutureWindowEnd
            )
        }
    }

    nonisolated static func menuBarEmptyStateText(
        menuBarRotationWindowMinutes: Int,
        hasLaterItemsInDropdownWindow: Bool
    ) -> String {
        guard hasLaterItemsInDropdownWindow else {
            return "No upcoming items"
        }

        return "No items in next \(menuBarRotationWindowDescription(minutes: menuBarRotationWindowMinutes))"
    }

    nonisolated static func menuBarRotationWindowDescription(minutes: Int) -> String {
        let clampedMinutes = max(1, minutes)
        let days = clampedMinutes / (24 * 60)
        let hours = (clampedMinutes % (24 * 60)) / 60
        let remainingMinutes = clampedMinutes % 60

        var components: [String] = []
        if days > 0 {
            components.append("\(days)d")
        }
        if hours > 0 {
            components.append("\(hours)h")
        }
        if remainingMinutes > 0 {
            components.append("\(remainingMinutes)m")
        }

        return components.prefix(2).joined(separator: " ")
    }

    nonisolated static func shouldIncludeInDropdownPreviewWindow(
        _ item: UpcomingItem,
        now: Date,
        futureWindowEnd: Date
    ) -> Bool {
        if item.kind == .reminder {
            return item.date <= now || item.date <= futureWindowEnd
        }

        if item.isAllDay {
            return shouldIncludeAllDayItem(
                startDate: item.date,
                endDate: item.endDate,
                now: now,
                futureWindowEnd: futureWindowEnd
            )
        }

        if item.kind == .reminder, item.date <= now {
            return true
        }

        if item.kind == .event,
           let endDate = item.endDate,
           item.date <= now,
           endDate > now {
            return true
        }

        return item.date >= now && item.date <= futureWindowEnd
    }

    nonisolated static func shouldIncludeAllDayItemInMenuBarRotation(
        startDate: Date,
        endDate: Date?,
        now: Date,
        futureWindowEnd: Date,
        calendar: Calendar = .current
    ) -> Bool {
        shouldIncludeAllDayItem(
            startDate: startDate,
            endDate: endDate,
            now: now,
            futureWindowEnd: futureWindowEnd,
            calendar: calendar
        )
    }


}
