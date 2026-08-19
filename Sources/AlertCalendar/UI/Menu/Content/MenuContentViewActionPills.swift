import AppKit
import CoreLocation
import MapKit
import SwiftUI

enum MenuActionControlMetrics {
    static let minimumHitTargetSize: CGFloat = 28
    static let symbolSize: CGFloat = 11
    static let labelSpacing: CGFloat = 4
    static let horizontalChrome: CGFloat = 12
    static let controlSpacing: CGFloat = 4
    static let leadingClearance: CGFloat = 16
    static let trailingInset: CGFloat = 6
}

struct MenuActionButtonGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: MenuActionControlMetrics.controlSpacing) {
            content
        }
    }
}

extension MenuContentView {
    func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.localizedCapitalized)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .accessibilityAddTraits(.isHeader)
    }

    func emptySectionRow(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    func timeRangeText(for item: UpcomingItem) -> String? {
        Self.timeRangeText(
            startDate: item.date,
            endDate: item.endDate,
            isAllDay: item.isAllDay
        )
    }

    @ViewBuilder
    func joinActionButton(for item: UpcomingItem) -> some View {
        Button {
            openMeetingFromDropdown(item)
        } label: {
            contextualActionLabel(title: "Join", systemImage: "video")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(minHeight: MenuActionControlMetrics.minimumHitTargetSize)
        .contentShape(Rectangle())
        .disabled(item.meetingURL == nil)
        .accessibilityLabel("Join meeting")
        .help("Join meeting")
    }

    func openMeetingFromDropdown(_ item: UpcomingItem) {
        NSApp.keyWindow?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            monitor.openMeeting(item)
        }
    }

    @ViewBuilder
    func skipActionButton(for item: UpcomingItem) -> some View {
        Button {
            monitor.skipItem(item)
        } label: {
            contextualActionLabel(title: "Skip", systemImage: "forward.end")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(minHeight: MenuActionControlMetrics.minimumHitTargetSize)
        .contentShape(Rectangle())
        .accessibilityLabel("Skip \(item.title)")
        .help("Skip this item")
    }

    @ViewBuilder
    func mapActionButton(for item: UpcomingItem, locationText: String) -> some View {
        Button {
            openMap(for: item, locationText: locationText)
        } label: {
            contextualActionLabel(title: "Map", systemImage: "map")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(minHeight: MenuActionControlMetrics.minimumHitTargetSize)
        .contentShape(Rectangle())
        .disabled(!Self.hasUsableContextualLocation(locationText))
        .accessibilityLabel("Open \(displayLocationName(from: locationText)) in Maps")
        .help("Open in Maps")
    }

    @ViewBuilder
    func completeActionButton(for item: UpcomingItem) -> some View {
        Button {
            monitor.markReminderCompleted(item)
        } label: {
            reminderCompletionActionLabel(color: Color(nsColor: item.calendarColor.nsColor))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(
            width: MenuActionControlMetrics.minimumHitTargetSize,
            height: MenuActionControlMetrics.minimumHitTargetSize
        )
        .contentShape(Rectangle())
        .accessibilityLabel("Complete \(item.title)")
        .help("Complete reminder")
    }

    func contextualActionLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: MenuActionControlMetrics.labelSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: MenuActionControlMetrics.symbolSize, weight: .medium))

            Text(title)
                .font(MenuMarkerMetrics.actionLabelFont)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    func reminderCompletionActionLabel(color: Color) -> some View {
        Image(systemName: "checkmark")
            .font(.system(size: MenuActionControlMetrics.symbolSize, weight: .semibold))
            .foregroundStyle(color)
            .frame(
                width: MenuActionControlMetrics.symbolSize,
                height: MenuActionControlMetrics.symbolSize
            )
    }

    nonisolated static func hasUsableContextualLocation(_ locationText: String?) -> Bool {
        guard let locationText else { return false }
        return !locationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let menuTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let menuDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "MMM d HH:mm"
        return formatter
    }()

    nonisolated static func measuredTextWidth(_ text: String, font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    static func timeRangeText(
        startDate: Date,
        endDate: Date?,
        isAllDay: Bool,
        calendar: Calendar = .current,
        timeText: @MainActor (Date) -> String = Self.timeText,
        dateTimeText: @MainActor (Date) -> String = Self.dateTimeText
    ) -> String? {
        guard !isAllDay else { return nil }
        let startText = timedEventClockText(
            date: startDate,
            startDate: startDate,
            endDate: endDate,
            calendar: calendar,
            timeText: timeText,
            dateTimeText: dateTimeText
        )
        guard let endDate, endDate > startDate else {
            return startText
        }

        let endText = timedEventClockText(
            date: endDate,
            startDate: startDate,
            endDate: endDate,
            calendar: calendar,
            timeText: timeText,
            dateTimeText: dateTimeText
        )
        return "\(startText)-\(endText)"
    }

    static func timedEventClockText(
        date: Date,
        startDate: Date,
        endDate: Date?,
        calendar: Calendar = .current,
        timeText: @MainActor (Date) -> String = Self.timeText,
        dateTimeText: @MainActor (Date) -> String = Self.dateTimeText
    ) -> String {
        if timedRangeSpansMultipleDays(
            startDate: startDate,
            endDate: endDate,
            calendar: calendar
        ) {
            return dateTimeText(date)
        }

        return timeText(date)
    }

    nonisolated static func timedRangeSpansMultipleDays(
        startDate: Date,
        endDate: Date?,
        calendar: Calendar = .current
    ) -> Bool {
        guard let endDate, endDate > startDate else { return false }
        return !calendar.isDate(startDate, inSameDayAs: endDate)
    }

    static func timeText(_ date: Date) -> String {
        menuTimeFormatter.string(from: date)
    }

    static func dateTimeText(_ date: Date) -> String {
        menuDateTimeFormatter.string(from: date)
    }

    func timeText(_ date: Date) -> String {
        Self.timeText(date)
    }

    func timedEventClockText(_ date: Date, for item: UpcomingItem) -> String {
        Self.timedEventClockText(
            date: date,
            startDate: item.date,
            endDate: item.endDate
        )
    }

    func eventTravelStartDate(for item: UpcomingItem) -> Date? {
        guard let travelMinutes = item.travelTimeMinutes, travelMinutes > 0 else { return nil }
        return item.date.addingTimeInterval(TimeInterval(-travelMinutes * 60))
    }

    func displayLocationName(from rawLocation: String) -> String {
        let trimmed = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return rawLocation }

        let primary = trimmed
            .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? trimmed

        return primary.isEmpty ? trimmed : primary
    }

    func shouldShowLocationRow(locationName: String, meetingURL: URL?) -> Bool {
        let normalizedLocation = locationName.lowercased()
        guard !normalizedLocation.isEmpty else { return false }

        if monitor.isVirtualLocationText(locationName) {
            return false
        }

        guard let meetingURL else { return true }

        if normalizedLocation.contains("microsoft teams"),
           meetingServiceName(for: meetingURL) == "Microsoft Teams" {
            return false
        }

        return true
    }
}
