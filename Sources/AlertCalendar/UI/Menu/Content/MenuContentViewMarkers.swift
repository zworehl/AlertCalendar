import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    func markerImage(for item: UpcomingItem) -> NSImage? {
        if item.kind == .reminder {
            return reminderMarkerImage(
                color: item.calendarColor,
                isFilled: hoveredReminderItemID == item.id
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

            let centerFill = NSBezierPath(ovalIn: rect.insetBy(dx: 4.0, dy: 4.0))
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
        let elapsed = max(Int(now.timeIntervalSince(dueDate)), 0)
        if elapsed < 60 {
            return "\(elapsed)s ago"
        }

        let days = elapsed / 86_400
        let hours = (elapsed % 86_400) / 3_600
        let minutes = (elapsed % 3_600) / 60
        let body: String

        if simplified {
            if days > 0 {
                body = "\(days)d"
            } else if hours > 0 {
                body = "\(hours)h"
            } else {
                body = "\(minutes)m"
            }
        } else if days > 0 {
            body = "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            body = "\(hours)h \(minutes)m"
        } else {
            body = "\(minutes)m"
        }

        return "\(body) ago"
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

        if let locationText = locationTextForMenuBarItem(item),
           shouldShowPhysicalMap(for: item, locationText: locationText) {
            return .location(locationText)
        }

        if !item.attendees.isEmpty {
            return .attendees(item.organizer, item.attendees)
        }

        return nil
    }

    func contextualCardMinimumWidth(for item: UpcomingItem) -> CGFloat {
        guard let previewKind = contextualPreviewKind(for: item) else {
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
            return ceil(max(392, (columnWidth * 2) + 12 + popupChromeWidth))
        case .location:
            return minimumSingleColumnDropdownWidth
        }
    }

    func queueItemMinimumWidth(for item: UpcomingItem) -> CGFloat {
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let detailFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let titleWidth = Self.measuredTextWidth(item.title, font: titleFont)
        let markerColumnWidth: CGFloat = 20
        let spacingAfterMarker: CGFloat = 8
        let contentSpacing: CGFloat = 6
        let popupChromeWidth = (dropdownOuterPadding * 2) + 16 + (8 * 2)

        var rightColumnWidth: CGFloat = 0
        let usesEventStyleLayout = item.kind == .event
        let allDayRightLabel = monitor.allDayLabel(for: item)
        let showRightTimeColumn = usesEventStyleLayout && (!item.isAllDay || allDayRightLabel != nil)
        if showRightTimeColumn {
            let startWidth = Self.measuredTextWidth(timeText(item.date), font: detailFont)
            let endWidth: CGFloat
            if let endDate = item.endDate, endDate > item.date {
                endWidth = Self.measuredTextWidth(timeText(endDate), font: detailFont)
            } else if let allDayRightLabel {
                endWidth = Self.measuredTextWidth(allDayRightLabel, font: detailFont)
            } else {
                endWidth = startWidth
            }
            rightColumnWidth = max(startWidth, endWidth)
        }

        let headerWidth = markerColumnWidth + spacingAfterMarker + titleWidth + (showRightTimeColumn ? (contentSpacing + rightColumnWidth) : 0)
        let hoveredWidth = markerColumnWidth + spacingAfterMarker + titleWidth + contentSpacing + hoverActionRowWidth(for: item)
        return ceil(max(headerWidth, hoveredWidth) + popupChromeWidth)
    }

    func hoverActionRowWidth(for item: UpcomingItem) -> CGFloat {
        let pillHorizontalPadding: CGFloat = 12
        let pillHeight: CGFloat = 18
        let pillSpacing: CGFloat = 4
        let trailingPadding: CGFloat = 2
        var widths: [CGFloat] = []

        if item.meetingURL != nil {
            let joinTextFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
            let joinTextWidth = Self.measuredTextWidth("Join", font: joinTextFont)
            let joinIconWidth: CGFloat = 11
            let joinInnerSpacing: CGFloat = 4
            widths.append(joinIconWidth + joinInnerSpacing + joinTextWidth + pillHorizontalPadding)
        }

        // The skip button uses the same action pill chrome around a 12pt icon.
        widths.append(12 + pillHorizontalPadding)

        guard !widths.isEmpty else { return 0 }
        let totalSpacing = pillSpacing * CGFloat(max(widths.count - 1, 0))
        return widths.reduce(0, +) + totalSpacing + trailingPadding + pillHeight
    }

    var contextualActionCandidates: [UpcomingItem] {
        let now = Date()

        return allEventItemsForContextualActions.filter { item in
            shouldShowContextualPreview(for: item, now: now)
                && contextualPreviewKind(for: item) != nil
        }
    }

    var contextualPreviewActionItems: [UpcomingItem] {
        Self.contextualActionItems(from: contextualActionCandidates, now: Date())
    }

    var footballContextualActionItems: [UpcomingItem] {
        Self.footballContextualActionItems(from: contextualActionCandidates, now: Date())
    }

    var displayedContextualActionItems: [UpcomingItem] {
        shouldUseSplitDropdownLayout ? footballContextualActionItems : contextualPreviewActionItems
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

    nonisolated static func shouldShowContextualMapPreview(
        for item: UpcomingItem,
        concurrentFootballMatchCount: Int
    ) -> Bool {
        guard item.footballMatch != nil else { return true }
        return concurrentFootballMatchCount < 3
    }

}
