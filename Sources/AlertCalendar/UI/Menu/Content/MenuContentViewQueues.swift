import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    func contextualActionSection(snapshot: LayoutSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            calendarSectionContainer(
                height: splitContextualPanelHeight(snapshot: snapshot),
                bottomPadding: snapshot.shouldUseSplitDropdownLayout ? splitPanelBottomPadding : nil
            ) {
                if snapshot.shouldUseSplitDropdownLayout {
                    ScrollView(.vertical, showsIndicators: true) {
                        contextualActionPanelContent(snapshot: snapshot)
                            .frame(width: contextualPanelContentWidth(snapshot: snapshot), alignment: .topLeading)
                            .background(
                                GeometryReader { proxy in
                                    contextualPanelMeasurementBackground(
                                        proxy: proxy,
                                        snapshot: snapshot
                                    )
                                }
                            )
                    }
                    .frame(width: contextualPanelContentWidth(snapshot: snapshot), alignment: .topLeading)
                    .clipped()
                } else {
                    contextualActionPanelContent(snapshot: snapshot)
                        .frame(width: contextualPanelContentWidth(snapshot: snapshot), alignment: .topLeading)
                        .background(
                            GeometryReader { proxy in
                                contextualPanelMeasurementBackground(
                                    proxy: proxy,
                                    snapshot: snapshot
                                )
                            }
                        )
                }
            }
        }
        .frame(width: contextualPanelOuterWidth(snapshot: snapshot), alignment: .topLeading)
        .clipped()
    }

    func contextualPanelMeasurementBackground(
        proxy: GeometryProxy,
        snapshot: LayoutSnapshot
    ) -> some View {
        Color.clear.preference(
            key: SplitContextualPanelMeasurementPreferenceKey.self,
            value: SplitContextualPanelMeasurement(
                key: snapshot.contextualPanelMeasurementKey,
                height: proxy.size.height
                    + panelTopPadding
                    + (snapshot.shouldUseSplitDropdownLayout
                        ? splitPanelBottomPadding
                        : panelBottomPadding)
            )
        )
    }

    func upcomingSection(snapshot: LayoutSnapshot) -> some View {
        calendarSectionContainer(
            height: upcomingSplitPanelHeight(snapshot: snapshot),
            bottomPadding: snapshot.shouldUseSplitDropdownLayout ? splitPanelBottomPadding : nil
        ) {
            if snapshot.queueItemsForActions.isEmpty {
                upcomingQueueRows(snapshot: snapshot)
            } else if shouldScrollUpcomingSplitPanel(snapshot: snapshot) {
                ScrollView(.vertical, showsIndicators: shouldScrollUpcomingSplitPanel(snapshot: snapshot)) {
                    upcomingQueueRows(snapshot: snapshot)
                        .frame(width: upcomingPanelContentWidth(snapshot: snapshot), alignment: .topLeading)
                }
                .frame(width: upcomingPanelContentWidth(snapshot: snapshot), alignment: .topLeading)
                .frame(height: upcomingSplitPanelContentHeight(snapshot: snapshot), alignment: .top)
                .clipped()
            } else if shouldScrollUpcomingSplitPanel(snapshot: snapshot) || !snapshot.shouldUseSplitDropdownLayout {
                ScrollView(.vertical, showsIndicators: true) {
                    upcomingQueueRows(snapshot: snapshot)
                        .frame(width: upcomingPanelContentWidth(snapshot: snapshot), alignment: .topLeading)
                }
                .frame(width: upcomingPanelContentWidth(snapshot: snapshot), alignment: .topLeading)
                .frame(
                    maxHeight: snapshot.shouldUseSplitDropdownLayout ? .infinity : upcomingListMaxHeight,
                    alignment: .top
                )
                .clipped()
            } else {
                upcomingQueueRows(snapshot: snapshot)
                    .frame(width: upcomingPanelContentWidth(snapshot: snapshot), alignment: .topLeading)
            }
        }
        .frame(width: upcomingPanelOuterWidth(snapshot: snapshot), alignment: .topLeading)
        .clipped()
    }

    @ViewBuilder
    func dropdownSummarySections(snapshot: LayoutSnapshot) -> some View {
        if settings.showAgendaSummary,
           monitor.agendaSummaryAvailability.isAvailable,
           monitor.agendaSummaryState != .unavailable {
            if snapshot.shouldUseSplitDropdownLayout {
                ScrollView(.vertical, showsIndicators: true) {
                    dropdownSummarySectionContent(snapshot: snapshot)
                }
                .frame(width: upcomingPanelOuterWidth(snapshot: snapshot), alignment: .topLeading)
                .frame(maxHeight: min(260, splitDropdownColumnHeightLimit * 0.52), alignment: .top)
                .clipped()
            } else {
                dropdownSummarySectionContent(snapshot: snapshot)
            }
        }
    }

    private func dropdownSummarySectionContent(snapshot: LayoutSnapshot) -> some View {
        agendaSummarySection(snapshot: snapshot)
        .frame(
            width: upcomingPanelOuterWidth(snapshot: snapshot),
            alignment: .topLeading
        )
    }

    func contextualActionPanelContent(snapshot: LayoutSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if snapshot.contextualSharedCompetitionIsActive {
                contextualSharedCompetitionHeader(snapshot: snapshot)
            }

            ForEach(Array(snapshot.displayedContextualActionItems.enumerated()), id: \.element.notificationKey) { index, item in
                contextualActionCard(
                    for: item,
                    showsFootballCompetitionLine: !snapshot.contextualSharedCompetitionIsActive,
                    snapshot: snapshot
                )

                if index < snapshot.displayedContextualActionItems.count - 1 {
                    Divider()
                }
            }
        }
    }

    func upcomingQueueRows(snapshot: LayoutSnapshot) -> AnyView {
        let entries = Self.upcomingQueueEntries(
            from: snapshot.queueItemsForActions,
            birthdayCalendarIDs: monitor.birthdayCalendarIDs
        )

        return AnyView(VStack(spacing: 0) {
            if entries.isEmpty {
                emptySectionRow("No upcoming items")
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider()
                    }

                    switch entry {
                    case .item(let item):
                        actionRow(
                            item: item,
                            actions: [.skip]
                        )
                    case .birthdayGroup(let group):
                        birthdayGroupRows(group)
                    }
                }
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SplitUpcomingPanelHeightPreferenceKey.self,
                    value: proxy.size.height + panelTopPadding + (snapshot.shouldUseSplitDropdownLayout ? splitPanelBottomPadding : panelBottomPadding)
                )
            }
        ))
    }

    var filteredAlertDescriptions: [String] {
        let now = displayReferenceDate
        let items = monitor.upcomingItems.filter { item in
            if let kindFilter, item.kind != kindFilter {
                return false
            }
            return CalendarMonitor.shouldAlertForItem(item, now: now, settings: settings)
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
            contextualItems: splitContextualActionItemsForSplitLayout,
            now: now,
            futureWindowEnd: dropdownFutureWindowEnd(now: now),
            maxItems: max(1, settings.maxListItems)
        )
    }

    var contextualPreviewKindsByKey: [String: ContextualPreviewKind] {
        Dictionary(
            uniqueKeysWithValues: contextualActionCandidates.compactMap { item in
                contextualPreviewKind(for: item).map { (item.notificationKey, $0) }
            }
        )
    }

    var nonFootballContextualActionItems: [UpcomingItem] {
        Self.contextualActionItems(
            from: contextualActionCandidates.filter { $0.footballMatch == nil },
            now: displayReferenceDate
        )
    }

    var splitContextualActionItemsForSplitLayout: [UpcomingItem] {
        Self.splitContextualActionItems(
            contextualItems: contextualPreviewActionItems + nonFootballContextualActionItems,
            footballItems: footballContextualActionItems,
            previewKindsByKey: contextualPreviewKindsByKey
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

    nonisolated static func splitContextualActionItems(
        contextualItems: [UpcomingItem],
        footballItems: [UpcomingItem],
        previewKindsByKey: [String: ContextualPreviewKind]
    ) -> [UpcomingItem] {
        var mergedItems: [UpcomingItem] = []
        var seenKeys: Set<String> = []

        for item in contextualItems + footballItems where seenKeys.insert(item.notificationKey).inserted {
            mergedItems.append(item)
        }

        return mergedItems.sorted { left, right in
            let leftPriority = splitContextualPriority(for: left, previewKindsByKey: previewKindsByKey)
            let rightPriority = splitContextualPriority(for: right, previewKindsByKey: previewKindsByKey)
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            return contextualItemSortPrecedes(left, right)
        }
    }

    nonisolated private static func splitContextualPriority(
        for item: UpcomingItem,
        previewKindsByKey: [String: ContextualPreviewKind]
    ) -> Int {
        if case .attendees = previewKindsByKey[item.notificationKey] {
            return 0
        }
        if item.footballMatch != nil {
            return 1
        }
        return 2
    }

    nonisolated private static func contextualItemSortPrecedes(_ left: UpcomingItem, _ right: UpcomingItem) -> Bool {
        if left.date != right.date {
            return left.date < right.date
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
