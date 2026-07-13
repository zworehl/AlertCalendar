import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    func markerImage(for item: UpcomingItem, isReminderFilled: Bool = false) -> NSImage? {
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

    func markerSymbolName(for item: UpcomingItem) -> String? {
        if monitor.isBirthdayItem(item) {
            return "gift.circle.fill"
        }
        if item.kind == .event, item.isAllDay {
            return "calendar.circle.fill"
        }
        return nil
    }

    func astronomyMarkerImage(for moment: AstronomyMoment) -> NSImage {
        if let image = AstronomyIconProvider.image(for: moment, pointSize: 13) {
            return image
        }
        return NSImage(size: NSSize(width: 16, height: 12))
    }

    func markerTopPadding(for item: UpcomingItem) -> CGFloat {
        item.kind == .reminder ? 0 : 2
    }

    func markerImageSize(for item: UpcomingItem) -> CGSize {
        if AstronomyMoment(eventTitle: item.title) != nil {
            return CGSize(width: 14, height: 14)
        }
        return CGSize(width: 12, height: 12)
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
            let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
            let timeFont = NSFont.systemFont(ofSize: 11, weight: .medium)
            let titleWidth = Self.measuredTextWidth(item.title, font: titleFont)
            let timeWidth = Self.measuredTextWidth(timeText(item.date), font: timeFont)

            let headerWidth =
                18 + 10 + titleWidth + 12 + timeWidth + 12 + 106 + 12
            let popupChromeWidth = (dropdownOuterPadding * 2) + 16
            return ceil(headerWidth + popupChromeWidth)
        case let .attendees(_, attendees):
            let detailFont = NSFont.systemFont(ofSize: 11, weight: .medium)
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
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let detailFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let accessoryWidth = MenuBarStatusLabel.accessorySymbolsWidth(
            symbolNames: monitor.menuBarAccessorySymbolNames(for: item),
            font: titleFont
        )
        let measuredTitleWidth = Self.measuredTextWidth(item.title, font: titleFont)
        let titleWidth = measuredTitleWidth + accessoryWidth
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

    func hoverActionRowWidth(
        for item: UpcomingItem,
        trailingInset: CGFloat = 0
    ) -> CGFloat {
        var widths: [CGFloat] = []

        if item.meetingURL != nil {
            widths.append(joinActionPillWidth())
        }

        widths.append(skipActionPillWidth())

        return actionButtonOverlayWidth(
            for: widths,
            trailingPadding: 2 + max(0, trailingInset)
        )
    }

    func contextualActionRowWidth(
        for item: UpcomingItem,
        locationText: String?,
        showsJoinButton: Bool
    ) -> CGFloat {
        var widths: [CGFloat] = [skipActionPillWidth()]

        if showsJoinButton, item.meetingURL != nil {
            widths.insert(joinActionPillWidth(), at: 0)
        }

        if let locationText,
           !locationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            widths.append(mapActionPillWidth())
        }

        return actionButtonOverlayWidth(for: widths, trailingPadding: 6)
    }

    func joinActionPillWidth() -> CGFloat {
        let pillHorizontalPadding: CGFloat = 12
        let joinTextFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let joinTextWidth = Self.measuredTextWidth("Join", font: joinTextFont)
        return joinTextWidth + pillHorizontalPadding
    }

    func mapActionPillWidth() -> CGFloat {
        let pillHorizontalPadding: CGFloat = 12
        let mapTextFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let mapTextWidth = Self.measuredTextWidth("Map", font: mapTextFont)
        let mapIconWidth: CGFloat = 11
        let mapInnerSpacing: CGFloat = 4
        return mapIconWidth + mapInnerSpacing + mapTextWidth + pillHorizontalPadding
    }

    func skipActionPillWidth() -> CGFloat {
        let pillHorizontalPadding: CGFloat = 12
        let skipTextFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let skipTextWidth = Self.measuredTextWidth("Skip", font: skipTextFont)
        return skipTextWidth + pillHorizontalPadding
    }

    func actionButtonOverlayWidth(for widths: [CGFloat], trailingPadding: CGFloat) -> CGFloat {
        let pillHeight: CGFloat = 18
        let pillSpacing: CGFloat = 4

        guard !widths.isEmpty else { return 0 }
        let totalSpacing = pillSpacing * CGFloat(max(widths.count - 1, 0))
        return widths.reduce(0, +) + totalSpacing + trailingPadding + pillHeight
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
