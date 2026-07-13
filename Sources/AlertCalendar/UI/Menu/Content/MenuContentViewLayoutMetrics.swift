import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    var dropdownMinimumWidth: CGFloat {
        if shouldUseSplitDropdownLayout {
            return splitDropdownWidth(
                contextualItems: splitContextualActionItemsForSplitLayout,
                previewKindsByKey: contextualPreviewKindsByKey
            )
        }

        return resolvedSingleColumnDropdownWidth(
            contextualWidth: singleColumnContextualMinimumWidth,
            queueWidth: singleColumnQueueMinimumWidth
        )
    }

    func contextualPanelOuterWidth(snapshot: LayoutSnapshot) -> CGFloat {
        if snapshot.shouldUseSplitDropdownLayout {
            return splitContextualPanelOuterWidth(
                contextualItems: snapshot.displayedContextualActionItems,
                previewKindsByKey: snapshot.contextualPreviewKindsByKey
            )
        }

        return singleColumnPanelOuterWidth(snapshot: snapshot)
    }

    func upcomingPanelOuterWidth(snapshot: LayoutSnapshot) -> CGFloat {
        if snapshot.shouldUseSplitDropdownLayout {
            return splitQueueColumnWidth
        }

        return singleColumnPanelOuterWidth(snapshot: snapshot)
    }

    func contextualPanelContentWidth(snapshot: LayoutSnapshot) -> CGFloat {
        panelContentWidth(forOuterWidth: contextualPanelOuterWidth(snapshot: snapshot))
    }

    func upcomingPanelContentWidth(snapshot: LayoutSnapshot) -> CGFloat {
        panelContentWidth(forOuterWidth: upcomingPanelOuterWidth(snapshot: snapshot))
    }

    private func singleColumnPanelOuterWidth(snapshot: LayoutSnapshot) -> CGFloat {
        max(
            minimumSingleColumnDropdownWidth - (dropdownOuterPadding * 2),
            snapshot.dropdownMinimumWidth - (dropdownOuterPadding * 2)
        )
    }

    private func panelContentWidth(forOuterWidth outerWidth: CGFloat) -> CGFloat {
        max(120, outerWidth - (panelHorizontalPadding * 2))
    }

    func splitDropdownWidth(
        contextualItems: [UpcomingItem],
        previewKindsByKey: [String: ContextualPreviewKind]
    ) -> CGFloat {
        splitContextualPanelOuterWidth(
            contextualItems: contextualItems,
            previewKindsByKey: previewKindsByKey
        )
            + splitColumnSpacing
            + splitQueueColumnWidth
            + (dropdownOuterPadding * 2)
    }

    func splitContextualPanelOuterWidth(
        contextualItems: [UpcomingItem],
        previewKindsByKey: [String: ContextualPreviewKind]
    ) -> CGFloat {
        let measuredDropdownWidth = contextualItems.reduce(minimumContextualPanelDropdownWidth) { partialResult, item in
            max(
                partialResult,
                contextualCardMinimumWidth(
                    for: item,
                    previewKind: previewKindsByKey[item.notificationKey]
                )
            )
        }
        return max(
            minimumContextualPanelDropdownWidth - (dropdownOuterPadding * 2),
            measuredDropdownWidth - (dropdownOuterPadding * 2)
        )
    }

    func resolvedSingleColumnDropdownWidth(
        contextualWidth: CGFloat,
        queueWidth: CGFloat
    ) -> CGFloat {
        let requiredWidth = max(
            minimumSingleColumnDropdownWidth,
            contextualWidth,
            queueWidth
        )
        return requiredWidth
    }

    var singleColumnContextualMinimumWidth: CGFloat {
        displayedContextualActionItems.reduce(minimumSingleColumnDropdownWidth) { partialResult, item in
            max(partialResult, contextualCardMinimumWidth(for: item))
        }
    }

    var singleColumnQueueMinimumWidth: CGFloat {
        queueItemsForActions.reduce(minimumSingleColumnDropdownWidth) { partialResult, item in
            max(partialResult, queueItemMinimumWidth(for: item))
        }
    }

    var splitDropdownColumnHeightLimit: CGFloat {
        let screenHeight = activeDropdownScreenVisibleFrame.height
        return min(splitDropdownMaxColumnHeight, max(360, screenHeight * 0.62))
    }

    func splitPanelContentHeight(bottomPadding: CGFloat? = nil) -> CGFloat {
        max(
            120,
            splitDropdownColumnHeightLimit - panelTopPadding - (bottomPadding ?? splitPanelBottomPadding)
        )
    }

    var dropdownVisibleHeightBudget: CGFloat {
        let screenHeight = activeDropdownScreenVisibleFrame.height
        return max(420, min(screenHeight - 140, screenHeight * 0.72))
    }

    var activeDropdownScreenVisibleFrame: CGRect {
        if let keyWindowFrame = NSApp.keyWindow?.screen?.visibleFrame {
            return keyWindowFrame
        }

        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreenFrame = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })?.visibleFrame {
            return mouseScreenFrame
        }

        return NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 960)
    }

    func shouldUseHeightConstrainedSplitLayout(
        contextualItems: [UpcomingItem],
        previewKindsByKey: [String: ContextualPreviewKind],
        queueItems: [UpcomingItem],
        alertCount: Int
    ) -> Bool {
        guard !contextualItems.isEmpty,
              !queueItems.isEmpty else {
            return false
        }

        let screenWidth = activeDropdownScreenVisibleFrame.width
        let requiredDropdownWidth = splitDropdownWidth(
            contextualItems: contextualItems,
            previewKindsByKey: previewKindsByKey
        )
        guard screenWidth >= requiredDropdownWidth + 32 else {
            return false
        }

        return estimatedSingleColumnDropdownHeight(
            contextualItems: contextualItems,
            queueItems: queueItems,
            alertCount: alertCount
        ) > dropdownVisibleHeightBudget
    }

    func estimatedSingleColumnDropdownHeight(
        contextualItems: [UpcomingItem],
        queueItems: [UpcomingItem],
        alertCount: Int
    ) -> CGFloat {
        let headerHeight: CGFloat = 28
        let footerHeight: CGFloat = 26
        var sectionHeights: [CGFloat] = []

        if alertCount > 0 {
            sectionHeights.append(CGFloat(alertCount) * 26 + 16)
        }

        if !contextualItems.isEmpty {
            sectionHeights.append(estimatedContextualPanelHeight(for: contextualItems))
        }

        sectionHeights.append(estimatedUpcomingPanelHeight(for: queueItems))

        let childCount = 2 + sectionHeights.count
        let verticalGaps = CGFloat(max(0, childCount - 1)) * 12
        return (dropdownOuterPadding * 2)
            + headerHeight
            + footerHeight
            + sectionHeights.reduce(0, +)
            + verticalGaps
    }

    func estimatedContextualPanelHeight(for items: [UpcomingItem]) -> CGFloat {
        let footballItemCount = Self.contextualFootballLayoutItemCount(from: items)
        let footballContentLevel = Self.contextualFootballContentLevel(for: footballItemCount)
        let contentHeight = items.enumerated().reduce(CGFloat(0)) { partialResult, pair in
            let dividerHeight: CGFloat = pair.offset == 0 ? 0 : 9
            return partialResult
                + dividerHeight
                + estimatedContextualCardHeight(
                    for: pair.element,
                    footballItemCount: footballItemCount,
                    footballContentLevel: footballContentLevel
                )
        }
        return contentHeight + panelTopPadding + panelBottomPadding
    }

    func estimatedContextualCardHeight(
        for item: UpcomingItem,
        footballItemCount: Int,
        footballContentLevel: FootballContextualContentLevel
    ) -> CGFloat {
        let previewKind = contextualPreviewKind(for: item)
        var height: CGFloat = 42

        switch previewKind {
        case let .attendees(organizer, attendees):
            let listHeight = MeetingAttendeesPreview.resolvedListHeight(
                attendeeCount: attendees.count,
                maximumHeight: 188,
                columnCount: 1
            )
            height += 6 + estimatedAttendeesPreviewHeight(
                organizer: organizer,
                listHeight: listHeight
            )
        case .location:
            height += 10 + 112
        case .daylight:
            height += 10 + 112
        case nil:
            break
        }

        if let footballMatch = item.footballMatch {
            if footballContentLevel.showsStats && footballMatch.statusState != .scheduled {
                height += estimatedFootballStatsHeight(for: footballMatch)
            } else if Self.shouldShowStandaloneContextualFootballOutcomeProbabilities(
                for: footballMatch,
                itemCount: footballItemCount
            ) {
                height += 18
            }
            if footballContentLevel.showsGoalScorers,
               footballMatch.totalGoals > 0 {
                height += estimatedFootballGoalScorersHeight(for: footballMatch)
            }
        }

        return height
    }

    func estimatedFootballStatsHeight(for match: FootballFixtureMatch) -> CGFloat {
        let headerHeight: CGFloat = Self.footballContextualScorePlacement(
            for: match,
            itemCount: 1
        ) == .stats ? 72 : 0
        let probabilityHeight: CGFloat = 19
        let rowHeight: CGFloat = 28
        let rowSpacing: CGFloat = 6
        let estimatedRows: CGFloat = 10
        let statsRowsHeight = (estimatedRows * rowHeight) + ((estimatedRows - 1) * rowSpacing)
        return headerHeight + probabilityHeight + statsRowsHeight + 18
    }

    func estimatedFootballGoalScorersHeight(for match: FootballFixtureMatch) -> CGFloat {
        let rowHeight: CGFloat = 18
        let rowSpacing: CGFloat = 4
        let verticalPadding: CGFloat = 12
        let visibleRows = max(1, CGFloat(match.totalGoals))
        return verticalPadding + (visibleRows * rowHeight) + ((visibleRows - 1) * rowSpacing)
    }

    func estimatedAttendeesPreviewHeight(
        organizer: MeetingOrganizer?,
        listHeight: CGFloat
    ) -> CGFloat {
        let organizerHeight: CGFloat = organizer == nil ? 0 : 58
        let dividerHeight: CGFloat = organizer == nil ? 0 : 1
        let inviteesHeaderHeight: CGFloat = 16
        let verticalSpacing: CGFloat = organizer == nil ? 10 : 30
        return organizerHeight
            + dividerHeight
            + inviteesHeaderHeight
            + listHeight
            + verticalSpacing
    }

    func estimatedUpcomingPanelHeight(for items: [UpcomingItem]) -> CGFloat {
        let rowHeight: CGFloat = 46
        let dividerHeight = CGFloat(max(0, items.count - 1))
        let contentHeight = items.isEmpty ? 34 : (CGFloat(items.count) * rowHeight) + dividerHeight
        return min(contentHeight, upcomingListMaxHeight) + panelTopPadding + panelBottomPadding
    }

    func splitPanelHeight(measuredHeight: CGFloat, snapshot: LayoutSnapshot) -> CGFloat? {
        guard snapshot.shouldUseSplitDropdownLayout else { return nil }
        guard measuredHeight > 0 else { return nil }
        return min(splitDropdownColumnHeightLimit, measuredHeight)
    }

    func splitContextualPanelMinimumHeight(
        snapshot: LayoutSnapshot,
        measuredRightColumnHeight: CGFloat? = nil
    ) -> CGFloat? {
        guard snapshot.shouldUseSplitDropdownLayout else { return nil }
        let measuredHeight = measuredRightColumnHeight ?? splitRightColumnHeight
        guard measuredHeight > 0 else { return nil }
        return measuredHeight
    }

    func upcomingSplitPanelHeight(snapshot: LayoutSnapshot) -> CGFloat? {
        splitPanelHeight(measuredHeight: splitUpcomingPanelHeight, snapshot: snapshot)
    }

    func upcomingSplitPanelContentHeight(snapshot: LayoutSnapshot) -> CGFloat {
        guard let panelHeight = upcomingSplitPanelHeight(snapshot: snapshot) else {
            return splitPanelContentHeight()
        }

        return max(0, panelHeight - panelTopPadding - splitPanelBottomPadding)
    }

    func shouldScrollUpcomingSplitPanel(snapshot: LayoutSnapshot) -> Bool {
        guard snapshot.shouldUseSplitDropdownLayout,
              let upcomingSplitPanelHeight = upcomingSplitPanelHeight(snapshot: snapshot) else {
            return false
        }

        return splitUpcomingPanelHeight > upcomingSplitPanelHeight + 0.5
    }

    func shouldShowUpcomingScrollIndicator(snapshot: LayoutSnapshot) -> Bool {
        guard !snapshot.queueItemsForActions.isEmpty else { return false }

        if snapshot.shouldUseSplitDropdownLayout {
            return shouldScrollUpcomingSplitPanel(snapshot: snapshot)
        }

        let contentHeight = max(
            0,
            splitUpcomingPanelHeight - panelTopPadding - panelBottomPadding
        )
        return contentHeight > upcomingListMaxHeight + 0.5
    }

    func upcomingActionTrailingInset(snapshot: LayoutSnapshot) -> CGFloat {
        Self.actionTrailingInset(
            showsVerticalScrollIndicator: shouldShowUpcomingScrollIndicator(snapshot: snapshot),
            scrollerWidth: NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay)
        )
    }

    nonisolated static func actionTrailingInset(
        showsVerticalScrollIndicator: Bool,
        scrollerWidth: CGFloat
    ) -> CGFloat {
        guard showsVerticalScrollIndicator else { return 0 }
        return ceil(max(0, scrollerWidth))
    }

    var shouldUseSplitDropdownLayout: Bool {
        shouldUseHeightConstrainedSplitLayout(
            contextualItems: splitContextualActionItemsForSplitLayout,
            previewKindsByKey: contextualPreviewKindsByKey,
            queueItems: queueItemsForSplitLayout,
            alertCount: filteredAlertDescriptions.count
        )
    }

    var sharedContextualFootballMatches: [FootballFixtureMatch]? {
        guard !displayedContextualActionItems.isEmpty else { return nil }

        let footballMatches = displayedContextualActionItems.compactMap(\.footballMatch)
        guard footballMatches.count == displayedContextualActionItems.count else { return nil }

        return footballMatches
    }

    var sharedContextualFootballCompetitionTitle: String? {
        guard let sharedContextualFootballMatches else { return nil }
        return FootballFixtureFormatter.sharedCompetitionTitle(for: sharedContextualFootballMatches)
    }

    var sharedContextualFootballCompetitionLogoPath: String? {
        guard sharedContextualFootballCompetitionTitle != nil else { return nil }
        return displayedContextualActionItems.first?.footballMenuBarDisplay?.competitionLocalLogoPath
    }

    var sharedContextualFootballCompetitionLogoURL: URL? {
        guard let sharedContextualFootballMatches,
              sharedContextualFootballCompetitionTitle != nil else {
            return nil
        }

        return sharedContextualFootballMatches.first?.competitionLogoURL
    }

    var contextualSharedCompetitionHeader: some View {
        contextualSharedCompetitionHeader(
            title: sharedContextualFootballCompetitionTitle ?? "",
            localPath: sharedContextualFootballCompetitionLogoPath,
            remoteURL: sharedContextualFootballCompetitionLogoURL
        )
    }

    func contextualSharedCompetitionHeader(snapshot: LayoutSnapshot) -> some View {
        contextualSharedCompetitionHeader(
            title: snapshot.sharedContextualFootballCompetitionTitle ?? "",
            localPath: snapshot.sharedContextualFootballCompetitionLogoPath,
            remoteURL: snapshot.sharedContextualFootballCompetitionLogoURL
        )
    }

    private func contextualSharedCompetitionHeader(
        title: String,
        localPath: String?,
        remoteURL: URL?
    ) -> some View {
        HStack(spacing: 6) {
            FootballCompetitionLogoView(
                localPath: localPath,
                remoteURL: remoteURL,
                placeholderSymbolSize: 11
            )

            Text("All listed matches are from \(title)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    var contextualSharedCompetitionIsActive: Bool {
        sharedContextualFootballCompetitionTitle != nil
    }
}
