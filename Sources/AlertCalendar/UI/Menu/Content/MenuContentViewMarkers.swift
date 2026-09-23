import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    @ViewBuilder
    func menuMarkerColumn(
        for item: UpcomingItem,
        isHovered: Bool = false,
        rowMinimumHeight: CGFloat = MenuMarkerMetrics.singleLineRowMinimumHeight,
        allowsReminderCompletion: Bool = false
    ) -> some View {
        MenuMarkerColumn {
            if item.kind == .reminder, allowsReminderCompletion {
                reminderCompletionMarkerButton(for: item, isHovered: isHovered)
            } else if let markerSymbol = markerSymbolName(for: item) {
                Image(systemName: markerSymbol)
                    .font(.system(size: MenuMarkerMetrics.symbolSize, weight: .regular))
                    .frame(
                        width: MenuMarkerMetrics.symbolSize,
                        height: MenuMarkerMetrics.symbolSize
                    )
                    .foregroundStyle(Color(nsColor: item.calendarColor.nsColor))
                    .padding(.top, markerTopPadding(for: item))
            } else if let image = markerImage(for: item, isReminderFilled: isHovered) {
                let markerSize = markerImageSize(for: item)
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: markerSize.width, height: markerSize.height)
                    .padding(.top, markerTopPadding(for: item))
            } else {
                Capsule()
                    .fill(Color(nsColor: item.calendarColor.nsColor))
                    .frame(
                        width: 4,
                        height: Self.dropdownCalendarMarkerHeight(
                            rowMinimumHeight: rowMinimumHeight
                        )
                    )
                    .padding(.top, MenuMarkerMetrics.markerFirstLineTopPadding)
            }
        }
    }

    @ViewBuilder
    func reminderCompletionMarkerButton(
        for item: UpcomingItem,
        isHovered: Bool
    ) -> some View {
        let markerSize = markerImageSize(for: item)

        Button {
            monitor.markReminderCompleted(item)
        } label: {
            Image(
                nsImage: reminderMarkerImage(
                    color: item.calendarColor.nsColor,
                    isFilled: isHovered
                )
            )
            .resizable()
            .interpolation(.high)
            .frame(width: markerSize.width, height: markerSize.height)
            .padding(.top, markerTopPadding(for: item))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("Complete \(item.title)")
        .help("Complete reminder")
    }

    func markerImage(for item: UpcomingItem, isReminderFilled: Bool = false) -> NSImage? {
        if let gameStore = item.gameStore {
            return GameStoreSymbolProvider.image(for: gameStore, size: MenuMarkerMetrics.symbolSize)
        }
        if item.kind == .reminder {
            return reminderMarkerImage(
                color: item.calendarColor.nsColor,
                isFilled: isReminderFilled
            )
        }
        guard let moment = AstronomyMoment(eventTitle: item.title) else { return nil }
        return astronomyMarkerImage(for: moment)
    }

    func reminderMarkerImage(color: NSColor, isFilled: Bool) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size)
        if isFilled {
            let outerRing = NSBezierPath(ovalIn: rect.insetBy(dx: 0.8, dy: 0.8))
            outerRing.lineWidth = 1.55
            color.withAlphaComponent(0.97).setStroke()
            outerRing.stroke()

            let centerFill = NSBezierPath(ovalIn: rect.insetBy(dx: 3.6, dy: 3.6))
            color.withAlphaComponent(0.98).setFill()
            centerFill.fill()
        } else {
            let outerPath = NSBezierPath(ovalIn: rect.insetBy(dx: 0.9, dy: 0.9))
            outerPath.lineWidth = 1.6
            color.withAlphaComponent(0.82).setStroke()
            outerPath.stroke()
        }

        return image
    }

    nonisolated static func reminderDueText(dueDate: Date, now: Date, simplified: Bool) -> String {
        AlertCalendarRelativeTimeFormatter.elapsedAgoText(
            from: dueDate,
            to: now,
            simplified: simplified
        )
    }

    nonisolated static func reminderScheduleText(
        for item: UpcomingItem,
        now: Date,
        simplified: Bool,
        timedText: String,
        calendar: Calendar = .current
    ) -> String {
        guard item.hasExplicitTime else {
            return AlertCalendarRelativeTimeFormatter.calendarDayRelativeText(
                for: item.date,
                relativeTo: now,
                calendar: calendar
            )
        }
        guard item.date <= now else { return timedText }
        return reminderDueText(
            dueDate: item.date,
            now: now,
            simplified: simplified
        )
    }

    func markerSymbolName(for item: UpcomingItem) -> String? {
        if monitor.isBirthdayItem(item) {
            return "gift.circle.fill"
        }
        if item.kind == .event, item.isAllDay, item.gameStore == nil {
            return "calendar.circle.fill"
        }
        return nil
    }

    func astronomyMarkerImage(for moment: AstronomyMoment) -> NSImage {
        if let image = AstronomyIconProvider.monochromeImage(
            for: moment,
            pointSize: MenuMarkerMetrics.symbolSize,
            tintColor: .labelColor
        ) {
            return image
        }
        return NSImage(
            size: NSSize(
                width: MenuMarkerMetrics.symbolSize,
                height: MenuMarkerMetrics.symbolSize
            )
        )
    }

    func markerTopPadding(for item: UpcomingItem) -> CGFloat {
        if let gameStore = item.gameStore {
            return Self.gameStoreMarkerTopPadding(for: gameStore)
        }
        return MenuMarkerMetrics.markerFirstLineTopPadding
    }

    nonisolated static func gameStoreMarkerTopPadding(for store: GameStore) -> CGFloat {
        switch store {
        case .steam:
            return 1
        case .nintendoSwitch:
            return MenuMarkerMetrics.markerFirstLineTopPadding
        case .xbox, .playStation:
            return 0
        }
    }

    func markerImageSize(for item: UpcomingItem) -> CGSize {
        CGSize(width: MenuMarkerMetrics.symbolSize, height: MenuMarkerMetrics.symbolSize)
    }

    enum ContextualPreviewKind: Equatable {
        case location(String)
        case attendees(MeetingOrganizer?, [MeetingAttendee])
        case daylight(AstronomyMoment)
    }

    func shouldShowContextualPreview(for item: UpcomingItem, now: Date) -> Bool {
        guard item.kind == .event, !item.isAllDay else { return false }

        if let endDate = item.endDate,
           item.date <= now,
           endDate > now {
            return true
        }

        return item.date >= now && item.date <= contextualPreviewWindowEnd(now: now)
    }

    func daylightPreviewMoment(for item: UpcomingItem) -> AstronomyMoment? {
        guard let moment = AstronomyMoment(eventTitle: item.title),
              AstronomyMoment.solarMoments.contains(moment) else {
            return nil
        }

        return moment
    }

    func contextualPreviewKind(for item: UpcomingItem) -> ContextualPreviewKind? {
        if let daylightMoment = daylightPreviewMoment(for: item) {
            return .daylight(daylightMoment)
        }

        if item.meetingURL == nil,
           let locationText = locationTextForMenuBarItem(item) {
            return .location(locationText)
        }

        if !item.attendees.isEmpty {
            return .attendees(item.organizer, item.attendees)
        }

        return nil
    }

    func contextualCardMinimumWidth(for item: UpcomingItem) -> CGFloat {
        contextualCardMinimumWidth(for: item, previewKind: contextualPreviewKind(for: item))
    }

    func contextualCardMinimumWidth(
        for item: UpcomingItem,
        previewKind: ContextualPreviewKind?
    ) -> CGFloat {
        guard let previewKind else {
            return minimumSingleColumnDropdownWidth
        }

        switch previewKind {
        case .daylight:
            let titleFont = MenuMarkerMetrics.rowTitleNSFont
            let timeFont = MenuMarkerMetrics.rowDetailNSFont
            let titleWidth = Self.measuredTextWidth(item.title, font: titleFont)
            let timeWidth = Self.measuredTextWidth(timeText(item.date), font: timeFont)

            let headerWidth =
                18 + 10 + titleWidth + 12 + timeWidth + 12 + 106 + 12
            let popupChromeWidth = (dropdownOuterPadding * 2) + 16
            return ceil(headerWidth + popupChromeWidth)
        case let .attendees(_, attendees):
            let detailFont = MenuMarkerMetrics.rowDetailNSFont
            let widestAttendeeWidth = attendees
                .prefix(6)
                .map { Self.measuredTextWidth($0.displayText, font: detailFont) }
                .max() ?? 140
            let iconAllowance: CGFloat = 22
            let columnWidth = min(max(148, widestAttendeeWidth + iconAllowance), 190)
            let popupChromeWidth = (dropdownOuterPadding * 2) + 16
            return ceil(max(320, columnWidth + popupChromeWidth))
        case .location:
            return minimumSingleColumnDropdownWidth
        }
    }

    func queueItemMinimumWidth(for item: UpcomingItem) -> CGFloat {
        let titleFont = MenuMarkerMetrics.rowTitleNSFont
        let detailFont = MenuMarkerMetrics.rowDetailNSFont
        let accessorySymbolNames = monitor.menuBarAccessorySymbolNames(for: item)
        let visibleTitle = dropdownVisibleTitle(for: item)
        let measuredTitleWidth = Self.measuredTextWidth(visibleTitle, font: titleFont)
        let titleWidth = Self.dropdownMeasuredTitleWidth(
            visibleTitle: visibleTitle,
            accessorySymbolNames: accessorySymbolNames,
            titleFont: titleFont
        )
        let hoveredTitleWidth = measuredTitleWidth
        let markerColumnWidth: CGFloat = 20
        let spacingAfterMarker: CGFloat = 8
        let contentSpacing: CGFloat = 6
        let popupChromeWidth = (dropdownOuterPadding * 2) + 16 + (8 * 2)

        var rightColumnWidth: CGFloat = 0
        let usesEventStyleLayout = item.kind == .event
        let now = displayReferenceDate
        let allDayRightLabel = monitor.allDayLabel(
            for: item,
            now: now,
            simplified: settings.useSimplifiedCountdown
        )
        let showRightTimeColumn = usesEventStyleLayout && (!item.isAllDay || allDayRightLabel != nil)
        if showRightTimeColumn {
            let startWidth = Self.measuredTextWidth(timedEventClockText(item.date, for: item), font: detailFont)
            let endWidth: CGFloat
            if let endDate = item.endDate, endDate > item.date {
                endWidth = Self.measuredTextWidth(timedEventClockText(endDate, for: item), font: detailFont)
            } else if let allDayRightLabel {
                endWidth = Self.measuredTextWidth(allDayRightLabel, font: detailFont)
            } else {
                endWidth = startWidth
            }
            rightColumnWidth = max(startWidth, endWidth)
        }

        let headerWidth = markerColumnWidth + spacingAfterMarker + titleWidth + (showRightTimeColumn ? (contentSpacing + rightColumnWidth) : 0)
        let hoveredWidth = markerColumnWidth + spacingAfterMarker + hoveredTitleWidth + contentSpacing + hoverActionRowWidth(for: item)
        return ceil(max(headerWidth, hoveredWidth) + popupChromeWidth)
    }

    static func dropdownMeasuredTitleWidth(
        visibleTitle: String,
        accessorySymbolNames: [String],
        titleFont: NSFont
    ) -> CGFloat {
        measuredTextWidth(visibleTitle, font: titleFont)
            + MenuBarStatusLabel.accessorySymbolsWidth(
                symbolNames: accessorySymbolNames,
                font: titleFont
            )
    }

    func joinActionPillWidth() -> CGFloat {
        MenuActionControlMetrics.minimumHitTargetSize
    }

    func mapActionPillWidth() -> CGFloat {
        MenuActionControlMetrics.minimumHitTargetSize
    }

    func openLinkActionPillWidth() -> CGFloat {
        MenuActionControlMetrics.minimumHitTargetSize
    }

    func skipActionPillWidth() -> CGFloat {
        MenuActionControlMetrics.minimumHitTargetSize
    }

    func completeActionPillWidth() -> CGFloat {
        MenuActionControlMetrics.minimumHitTargetSize
    }

    func actionButtonOverlayWidth(for widths: [CGFloat], trailingPadding: CGFloat) -> CGFloat {
        guard !widths.isEmpty else { return 0 }
        let totalSpacing = MenuActionControlMetrics.controlSpacing * CGFloat(max(widths.count - 1, 0))
        return widths.reduce(0, +)
            + totalSpacing
            + trailingPadding
            + MenuActionControlMetrics.leadingClearance
    }

    var contextualActionCandidates: [UpcomingItem] {
        let now = displayReferenceDate

        return allEventItemsForContextualActions.filter { item in
            shouldShowContextualPreview(for: item, now: now)
                && contextualPreviewKind(for: item) != nil
        }
    }

    var contextualPreviewActionItems: [UpcomingItem] {
        Self.contextualActionItems(from: contextualActionCandidates, now: displayReferenceDate)
    }

    var footballContextualActionItems: [UpcomingItem] {
        Self.footballContextualActionItems(from: contextualActionCandidates, now: displayReferenceDate)
    }

    var displayedContextualActionItems: [UpcomingItem] {
        shouldUseSplitDropdownLayout ? splitContextualActionItemsForSplitLayout : contextualPreviewActionItems
    }

    nonisolated static func contextualActionItems(
        from candidates: [UpcomingItem],
        now: Date,
        calendar: Calendar = .current
    ) -> [UpcomingItem] {
        let sortedCandidates = candidates.sorted { left, right in
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

        let activeCandidates = sortedCandidates.filter { item in
            guard let endDate = item.endDate else { return false }
            return item.date <= now && endDate > now
        }
        if !activeCandidates.isEmpty {
            return activeCandidates
        }

        guard let anchor = sortedCandidates.first else { return [] }
        let concurrent = sortedCandidates.filter {
            calendar.isDate($0.date, equalTo: anchor.date, toGranularity: .minute)
        }
        return concurrent.isEmpty ? [anchor] : concurrent
    }

    nonisolated static func footballContextualActionItems(
        from candidates: [UpcomingItem],
        now: Date,
        calendar: Calendar = .current
    ) -> [UpcomingItem] {
        contextualActionItems(
            from: candidates.filter { $0.footballMatch != nil },
            now: now,
            calendar: calendar
        )
    }

    nonisolated static func contextualFootballLayoutItemCount(from displayedContextualItems: [UpcomingItem]) -> Int {
        displayedContextualItems.contains { $0.footballMatch != nil } ? displayedContextualItems.count : 0
    }

    nonisolated static func shouldShowContextualMapPreview(
        for item: UpcomingItem,
        contextualItemCount: Int
    ) -> Bool {
        guard item.footballMatch != nil else { return true }
        return contextualItemCount < 3
    }

}
