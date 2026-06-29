import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    struct LayoutSnapshot {
        let filteredAlertDescriptions: [String]
        let contextualActionCandidates: [UpcomingItem]
        let contextualPreviewActionItems: [UpcomingItem]
        let footballContextualActionItems: [UpcomingItem]
        let displayedContextualActionItems: [UpcomingItem]
        let contextualPreviewKindsByKey: [String: ContextualPreviewKind]
        let queueItemsSource: [UpcomingItem]
        let queueItemsForSingleColumnLayout: [UpcomingItem]
        let queueItemsForSplitLayout: [UpcomingItem]
        let queueItemsForActions: [UpcomingItem]
        let shouldUseSplitDropdownLayout: Bool
        let dropdownMinimumWidth: CGFloat
        let sharedContextualFootballMatches: [FootballFixtureMatch]?
        let sharedContextualFootballCompetitionTitle: String?
        let sharedContextualFootballCompetitionLogoPath: String?
        let sharedContextualFootballCompetitionLogoURL: URL?
        let contextualFootballContentLevel: FootballContextualContentLevel

        var contextualSharedCompetitionIsActive: Bool {
            sharedContextualFootballCompetitionTitle != nil
        }

        func contextualPreviewKind(for item: UpcomingItem) -> ContextualPreviewKind? {
            contextualPreviewKindsByKey[item.notificationKey]
        }
    }

    var layoutSnapshot: LayoutSnapshot {
        let now = displayReferenceDate
        let futureWindowEnd = dropdownFutureWindowEnd(now: now)
        let allDayItems = monitor.allDayEventItems
        let eventWindowItems = monitor.upcomingItems.filter {
            $0.kind == .event && Self.shouldIncludeInDropdownTimeWindow(
                $0,
                now: now,
                futureWindowEnd: futureWindowEnd
            )
        }
        let allEventItems = deduplicatedItems((allDayItems + eventWindowItems).sorted { $0.date < $1.date })
        var contextualPreviewKindsByKey: [String: ContextualPreviewKind] = [:]
        let contextualCandidates = allEventItems.filter { item in
            guard shouldShowContextualPreview(for: item, now: now),
                  let previewKind = contextualPreviewKind(for: item) else {
                return false
            }

            contextualPreviewKindsByKey[item.notificationKey] = previewKind
            return true
        }
        let contextualPreviewItems = Self.contextualActionItems(
            from: contextualCandidates,
            now: now
        )
        let nonFootballContextualItems = Self.contextualActionItems(
            from: contextualCandidates.filter { $0.footballMatch == nil },
            now: now
        )
        let footballContextualItems = Self.footballContextualActionItems(
            from: contextualCandidates,
            now: now
        )
        let splitContextualItems = Self.splitContextualActionItems(
            contextualItems: contextualPreviewItems + nonFootballContextualItems,
            footballItems: footballContextualItems,
            previewKindsByKey: contextualPreviewKindsByKey
        )

        let queueWindowItems = monitor.upcomingItems.filter {
            ($0.kind == .event || $0.kind == .reminder) && Self.shouldIncludeInDropdownTimeWindow(
                $0,
                now: now,
                futureWindowEnd: futureWindowEnd
            )
        }
        let queueSource = deduplicatedItems((allDayItems + queueWindowItems).sorted { $0.date < $1.date })
        let singleColumnQueueItems = Self.queueItemsForActions(
            from: queueSource,
            contextualItems: contextualPreviewItems,
            now: now,
            futureWindowEnd: futureWindowEnd,
            maxItems: max(1, settings.maxListItems)
        )
        let splitQueueItems = Self.queueItemsForActions(
            from: queueSource,
            contextualItems: splitContextualItems,
            now: now,
            futureWindowEnd: futureWindowEnd,
            maxItems: max(1, settings.maxListItems)
        )
        let usesSplitLayout = !footballContextualItems.isEmpty && !splitQueueItems.isEmpty
        let displayedContextualItems = usesSplitLayout ? splitContextualItems : contextualPreviewItems
        let displayedQueueItems = usesSplitLayout ? splitQueueItems : singleColumnQueueItems
        let dropdownMinimumWidth: CGFloat = {
            guard !usesSplitLayout else { return dropdownPreferredWidth }
            let contextualWidth = displayedContextualItems.reduce(minimumSingleColumnDropdownWidth) { partialResult, item in
                max(
                    partialResult,
                    contextualCardMinimumWidth(
                        for: item,
                        previewKind: contextualPreviewKindsByKey[item.notificationKey]
                    )
                )
            }
            let queueWidth = displayedQueueItems.reduce(minimumSingleColumnDropdownWidth) { partialResult, item in
                max(partialResult, queueItemMinimumWidth(for: item))
            }
            return max(minimumSingleColumnDropdownWidth, contextualWidth, queueWidth)
        }()
        let footballMatches: [FootballFixtureMatch]? = {
            guard !displayedContextualItems.isEmpty else { return nil }
            let matches = displayedContextualItems.compactMap(\.footballMatch)
            guard matches.count == displayedContextualItems.count else { return nil }
            return matches
        }()
        let sharedCompetitionTitle = footballMatches.flatMap {
            FootballFixtureFormatter.sharedCompetitionTitle(for: $0)
        }

        return LayoutSnapshot(
            filteredAlertDescriptions: filteredAlertDescriptions,
            contextualActionCandidates: contextualCandidates,
            contextualPreviewActionItems: contextualPreviewItems,
            footballContextualActionItems: footballContextualItems,
            displayedContextualActionItems: displayedContextualItems,
            contextualPreviewKindsByKey: contextualPreviewKindsByKey,
            queueItemsSource: queueSource,
            queueItemsForSingleColumnLayout: singleColumnQueueItems,
            queueItemsForSplitLayout: splitQueueItems,
            queueItemsForActions: displayedQueueItems,
            shouldUseSplitDropdownLayout: usesSplitLayout,
            dropdownMinimumWidth: dropdownMinimumWidth,
            sharedContextualFootballMatches: footballMatches,
            sharedContextualFootballCompetitionTitle: sharedCompetitionTitle,
            sharedContextualFootballCompetitionLogoPath: sharedCompetitionTitle == nil ? nil : displayedContextualItems.first?.footballMenuBarDisplay?.competitionLocalLogoPath,
            sharedContextualFootballCompetitionLogoURL: sharedCompetitionTitle == nil ? nil : footballMatches?.first?.competitionLogoURL,
            contextualFootballContentLevel: Self.contextualFootballContentLevel(
                for: displayedContextualItems.filter { $0.footballMatch != nil }.count
            )
        )
    }

    func contextualActionSection(snapshot: LayoutSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            calendarSectionContainer(
                height: contextualSplitPanelHeight(snapshot: snapshot),
                bottomPadding: snapshot.shouldUseSplitDropdownLayout ? splitPanelBottomPadding : nil
            ) {
                if shouldScrollContextualSplitPanel(snapshot: snapshot) {
                    ScrollView(.vertical, showsIndicators: true) {
                        contextualActionPanelContent(snapshot: snapshot)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    contextualActionPanelContent(snapshot: snapshot)
                }
            }
        }
    }

    func upcomingSection(snapshot: LayoutSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            calendarSectionContainer(
                height: upcomingSplitPanelHeight(snapshot: snapshot),
                bottomPadding: snapshot.shouldUseSplitDropdownLayout ? splitPanelBottomPadding : nil
            ) {
                if snapshot.queueItemsForActions.isEmpty {
                    upcomingQueueRows(snapshot: snapshot)
                } else if shouldScrollUpcomingSplitPanel(snapshot: snapshot) || !snapshot.shouldUseSplitDropdownLayout {
                    ScrollView(.vertical, showsIndicators: true) {
                        upcomingQueueRows(snapshot: snapshot)
                    }
                    .frame(
                        maxHeight: snapshot.shouldUseSplitDropdownLayout ? .infinity : upcomingListMaxHeight,
                        alignment: .top
                    )
                } else {
                    upcomingQueueRows(snapshot: snapshot)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SplitContextualPanelHeightPreferenceKey.self,
                    value: proxy.size.height + panelTopPadding + (snapshot.shouldUseSplitDropdownLayout ? splitPanelBottomPadding : panelBottomPadding)
                )
            }
        )
    }

    func upcomingQueueRows(snapshot: LayoutSnapshot) -> some View {
        VStack(spacing: 0) {
            if snapshot.queueItemsForActions.isEmpty {
                emptySectionRow("No upcoming items")
            } else {
                ForEach(Array(snapshot.queueItemsForActions.enumerated()), id: \.element.notificationKey) { index, item in
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
                    value: proxy.size.height + panelTopPadding + (snapshot.shouldUseSplitDropdownLayout ? splitPanelBottomPadding : panelBottomPadding)
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
