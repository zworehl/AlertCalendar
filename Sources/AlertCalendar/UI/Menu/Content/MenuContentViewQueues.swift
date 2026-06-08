import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    var contextualActionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            calendarSectionContainer(
                height: shouldUseSplitDropdownLayout ? splitSharedPanelHeight : nil,
                bottomPadding: shouldUseSplitDropdownLayout ? splitPanelBottomPadding : nil
            ) {
                if shouldScrollContextualSplitPanel {
                    ScrollView(.vertical, showsIndicators: true) {
                        contextualActionPanelContent
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    contextualActionPanelContent
                }
            }
        }
    }

    var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            calendarSectionContainer(
                height: shouldUseSplitDropdownLayout ? splitSharedPanelHeight : nil,
                bottomPadding: shouldUseSplitDropdownLayout ? splitPanelBottomPadding : nil
            ) {
                if queueItemsForActions.isEmpty {
                    upcomingQueueRows
                } else if shouldScrollUpcomingSplitPanel || !shouldUseSplitDropdownLayout {
                    ScrollView(.vertical, showsIndicators: true) {
                        upcomingQueueRows
                    }
                    .frame(
                        maxHeight: shouldUseSplitDropdownLayout ? .infinity : upcomingListMaxHeight,
                        alignment: .top
                    )
                } else {
                    upcomingQueueRows
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    var contextualActionPanelContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if contextualSharedCompetitionIsActive {
                contextualSharedCompetitionHeader
            }

            ForEach(Array(displayedContextualActionItems.enumerated()), id: \.element.notificationKey) { index, item in
                contextualActionCard(
                    for: item,
                    showsFootballCompetitionLine: !contextualSharedCompetitionIsActive
                )

                if index < displayedContextualActionItems.count - 1 {
                    Divider()
                }
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SplitContextualPanelHeightPreferenceKey.self,
                    value: proxy.size.height + panelTopPadding + (shouldUseSplitDropdownLayout ? splitPanelBottomPadding : panelBottomPadding)
                )
            }
        )
    }

    var upcomingQueueRows: some View {
        VStack(spacing: 0) {
            if queueItemsForActions.isEmpty {
                emptySectionRow("No upcoming items")
            } else {
                ForEach(Array(queueItemsForActions.enumerated()), id: \.element.notificationKey) { index, item in
                    if index > 0 {
                        Divider()
                    }
                    actionRow(item: item, actions: [.skip])
                }
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SplitUpcomingPanelHeightPreferenceKey.self,
                    value: proxy.size.height + panelTopPadding + (shouldUseSplitDropdownLayout ? splitPanelBottomPadding : panelBottomPadding)
                )
            }
        )
    }

    var filteredAlertDescriptions: [String] {
        let now = displayReferenceDate
        let leadSeconds = TimeInterval(settings.alertLeadMinutes * 60)
        let items = monitor.upcomingItems.filter { item in
            guard AstronomyMoment(eventTitle: item.title) == nil else { return false }
            if let kindFilter, item.kind != kindFilter {
                return false
            }
            return CalendarMonitor.shouldAlertForItem(item, now: now, leadSeconds: leadSeconds)
        }

        return items.map {
            CalendarMonitor.alertDescription(for: $0, now: now)
        }
    }

    var shouldShowSilenceButton: Bool {
        guard let activeAlertItem = monitor.activeAlertItem else { return false }
        guard let kindFilter else { return true }
        return activeAlertItem.kind == kindFilter
    }

    var allEventItemsForContextualActions: [UpcomingItem] {
        let now = displayReferenceDate
        let allDayItems = monitor.allDayEventItems
        let timedItems = monitor.upcomingItems.filter {
            $0.kind == .event && Self.shouldIncludeInDropdownTimeWindow(
                $0,
                now: now,
                futureWindowEnd: dropdownFutureWindowEnd(now: now)
            )
        }
        return deduplicatedItems((allDayItems + timedItems).sorted { $0.date < $1.date })
    }

    var queueItemsForActions: [UpcomingItem] {
        shouldUseSplitDropdownLayout ? queueItemsForSplitLayout : queueItemsForSingleColumnLayout
    }

    var queueItemsSource: [UpcomingItem] {
        let now = displayReferenceDate
        let allDayItems = monitor.allDayEventItems
        let timedItems = monitor.upcomingItems.filter {
            ($0.kind == .event || $0.kind == .reminder) && Self.shouldIncludeInDropdownTimeWindow(
                $0,
                now: now,
                futureWindowEnd: dropdownFutureWindowEnd(now: now)
            )
        }
        return deduplicatedItems((allDayItems + timedItems).sorted { $0.date < $1.date })
    }

    var queueItemsForSingleColumnLayout: [UpcomingItem] {
        let now = displayReferenceDate
        return Self.queueItemsForActions(
            from: queueItemsSource,
            contextualItems: contextualPreviewActionItems,
            now: now,
            futureWindowEnd: dropdownFutureWindowEnd(now: now),
            maxItems: max(1, settings.maxListItems)
        )
    }

    var queueItemsForSplitLayout: [UpcomingItem] {
        let now = displayReferenceDate
        return Self.queueItemsForActions(
            from: queueItemsSource,
            contextualItems: footballContextualActionItems,
            now: now,
            futureWindowEnd: dropdownFutureWindowEnd(now: now),
            maxItems: max(1, settings.maxListItems)
        )
    }

    func dropdownFutureWindowEnd(now: Date) -> Date {
        now.addingTimeInterval(Double(settings.lookAheadHours) * 3600)
    }

    func contextualPreviewWindowEnd(now: Date) -> Date {
        let maximumLeadMinutes = max(5, settings.lookAheadHours * 60)
        let clampedLeadMinutes = max(5, min(maximumLeadMinutes, settings.contextualPreviewLeadMinutes))
        let contextualWindowEnd = now.addingTimeInterval(Double(clampedLeadMinutes) * 60)
        return min(dropdownFutureWindowEnd(now: now), contextualWindowEnd)
    }

    nonisolated static func queueItemsForActions(
        from items: [UpcomingItem],
        contextualItems: [UpcomingItem],
        now: Date,
        futureWindowEnd: Date,
        maxItems: Int
    ) -> [UpcomingItem] {
        let contextualNotificationKeys = Set(contextualItems.map(\.notificationKey))
        let contextualFootballMatchIDs = Set(contextualItems.compactMap { $0.footballMatch?.id })
        let filtered = items.filter { item in
            shouldIncludeInUpcomingQueue(
                item,
                contextualNotificationKeys: contextualNotificationKeys,
                contextualFootballMatchIDs: contextualFootballMatchIDs,
                now: now,
                futureWindowEnd: futureWindowEnd
            )
        }
        return Array(filtered.prefix(max(1, maxItems)))
    }

    nonisolated static func shouldIncludeInDropdownTimeWindow(
        _ item: UpcomingItem,
        now: Date,
        futureWindowEnd: Date
    ) -> Bool {
        if item.isAllDay {
            return CalendarMonitor.shouldIncludeAllDayItem(
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

    nonisolated static func shouldIncludeInUpcomingQueue(
        _ item: UpcomingItem,
        contextualNotificationKeys: Set<String>,
        contextualFootballMatchIDs: Set<String>,
        now: Date,
        futureWindowEnd: Date
    ) -> Bool {
        guard shouldIncludeInDropdownTimeWindow(item, now: now, futureWindowEnd: futureWindowEnd) else {
            return false
        }

        if contextualNotificationKeys.contains(item.notificationKey) {
            return false
        }

        guard let footballMatch = item.footballMatch else {
            return true
        }

        if contextualFootballMatchIDs.contains(footballMatch.id) {
            return false
        }

        if footballMatch.statusState == .inProgress || item.date <= now {
            return false
        }

        return true
    }

    func deduplicatedItems(_ items: [UpcomingItem]) -> [UpcomingItem] {
        var seen: Set<String> = []
        var unique: [UpcomingItem] = []
        unique.reserveCapacity(items.count)

        for item in items {
            if seen.insert(item.notificationKey).inserted {
                unique.append(item)
            }
        }
        return unique
    }

    enum MenuAction {
        case skip
        case complete
    }

}
