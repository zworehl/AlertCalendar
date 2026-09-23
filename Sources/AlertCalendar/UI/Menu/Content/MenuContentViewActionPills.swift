import AppKit
import CoreLocation
import MapKit
import SwiftUI

enum MenuActionControlMetrics {
    static let minimumHitTargetSize: CGFloat = 28
    static let symbolSize: CGFloat = 11
    static let controlSpacing: CGFloat = 0
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
        .fixedSize(horizontal: true, vertical: true)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlColor))
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
        MenuActionButton(systemImage: "video", toolTip: "Join meeting", accessibilityLabel: "Join meeting") {
            openMeetingFromDropdown(item)
        }
        .frame(width: MenuActionControlMetrics.minimumHitTargetSize, height: MenuActionControlMetrics.minimumHitTargetSize)
        .disabled(item.meetingURL == nil)
    }

    func openMeetingFromDropdown(_ item: UpcomingItem) {
        NSApp.keyWindow?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            monitor.openMeeting(item)
        }
    }

    @ViewBuilder
    func openLinkActionButton(for item: UpcomingItem) -> some View {
        MenuActionButton(systemImage: "link", toolTip: "Open link", accessibilityLabel: "Open link for \(item.title)") {
            openLinkFromDropdown(item)
        }
        .frame(width: MenuActionControlMetrics.minimumHitTargetSize, height: MenuActionControlMetrics.minimumHitTargetSize)
        .disabled(item.openLinkURL == nil)
    }

    func openLinkFromDropdown(_ item: UpcomingItem) {
        guard let url = item.openLinkURL else { return }
        NSApp.keyWindow?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            AlertCalendarWorkspace.open(url)
        }
    }

    @ViewBuilder
    func skipActionButton(for item: UpcomingItem) -> some View {
        MenuActionButton(systemImage: "forward.end", toolTip: "Skip this item", accessibilityLabel: "Skip \(item.title)") {
            monitor.skipItem(item)
        }
        .frame(width: MenuActionControlMetrics.minimumHitTargetSize, height: MenuActionControlMetrics.minimumHitTargetSize)
    }

    @ViewBuilder
    func mapActionButton(for item: UpcomingItem, locationText: String) -> some View {
        MenuActionButton(
            systemImage: "map",
            toolTip: "Open in Maps",
            accessibilityLabel: "Open \(displayLocationName(from: locationText)) in Maps"
        ) {
            openMap(for: item, locationText: locationText)
        }
        .frame(width: MenuActionControlMetrics.minimumHitTargetSize, height: MenuActionControlMetrics.minimumHitTargetSize)
        .disabled(!Self.hasUsableContextualLocation(locationText))
    }

    @ViewBuilder
    func completeActionButton(for item: UpcomingItem) -> some View {
        MenuActionButton(systemImage: "checkmark.circle", toolTip: "Complete reminder", accessibilityLabel: "Complete \(item.title)") {
            monitor.markReminderCompleted(item)
        }
        .frame(width: MenuActionControlMetrics.minimumHitTargetSize, height: MenuActionControlMetrics.minimumHitTargetSize)
    }

    nonisolated static func hasUsableContextualLocation(_ locationText: String?) -> Bool {
        guard let locationText else { return false }
        return !locationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !CalendarMonitor.containsWebURL(in: locationText)
    }

    static let menuTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AlertCalendarLanguage.english
        formatter.dateStyle = .none
        formatter.dateFormat = AlertCalendarLanguage.uses24HourTime() ? "HH:mm" : "h:mm a"
        return formatter
    }()

    static let menuDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AlertCalendarLanguage.english
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

        if CalendarMonitor.containsWebURL(in: locationName) {
            return false
        }

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
