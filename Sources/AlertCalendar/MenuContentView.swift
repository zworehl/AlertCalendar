import AppKit
import CoreLocation
import MapKit
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var monitor: CalendarMonitor
    @Environment(\.openWindow) private var openWindow
    let kindFilter: CalendarItemKind?
    let headerTitle: String

    @AppStorage(DefaultsKeys.alertLeadMinutes) private var alertLeadMinutes = 5
    @AppStorage(DefaultsKeys.maxListItems) private var maxListItems = 8
    @State private var hoveredReminderItemID: String?
    @State private var hoveredActionRowKey: String?
    private let dropdownWidth: CGFloat = 520
    private let dropdownMinHeight: CGFloat = 620
    private let upcomingListMaxHeight: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView

            if !filteredAlertDescriptions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(filteredAlertDescriptions, id: \.self) { alertText in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                                .padding(.top, 1)
                            Text(alertText)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.red.opacity(0.10))
                )
            }

            if !contextualActionItems.isEmpty {
                sectionHeader("ACTIONS")
                calendarSectionContainer {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(contextualActionItems.enumerated()), id: \.element.notificationKey) { index, item in
                            let locationText = locationTextForMenuBarItem(item)
                            let shouldShowMapForItem = shouldShowPhysicalMap(for: item, locationText: locationText)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    Spacer(minLength: 8)

                                    if shouldShowMapForItem,
                                       let locationText {
                                        if let mapURL = mapURL(for: locationText) {
                                            Button {
                                                NSWorkspace.shared.open(mapURL)
                                            } label: {
                                                Label("Map", systemImage: "map")
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                }

                                if shouldShowMapForItem,
                                   let locationText {
                                    MiniLocationMapView(locationText: locationText)
                                        .id("\(item.notificationKey)|\(locationText)")
                                }
                            }

                            if index < contextualActionItems.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }

            sectionHeader("UPCOMING")
            calendarSectionContainer {
                if queueItemsForActions.isEmpty {
                    emptySectionRow("No upcoming items")
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 0) {
                            ForEach(Array(queueItemsForActions.enumerated()), id: \.element.notificationKey) { index, item in
                                if index > 0 {
                                    Divider()
                                }
                                actionRow(item: item, actions: [.skip])
                            }
                        }
                    }
                    .frame(maxHeight: upcomingListMaxHeight)
                }
            }

            HStack {
                if monitor.hasSkippedItems() {
                    Button("Restore Skipped") {
                        monitor.restoreSkippedItems()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if shouldShowSilenceButton {
                    Button("Silence Alert") {
                        monitor.silenceCurrentAlert()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.link)
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: dropdownWidth, alignment: .leading)
        .frame(minHeight: dropdownMinHeight, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: false)
        .onChange(of: alertLeadMinutes) { _ in
            monitor.refreshNow()
        }
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.headerDateFormatter.string(from: Date()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(headerTitle)
                    .font(.title3.weight(.semibold))
            }

            Spacer()

            Button {
                monitor.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh")

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: WindowMetadata.preferencesID)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
        }
    }

    private func calendarSectionContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var filteredAlertDescriptions: [String] {
        let now = Date()
        let leadSeconds = TimeInterval(max(1, alertLeadMinutes) * 60)
        let items = monitor.upcomingItems.filter { item in
            guard item.kind != .weather else { return false }
            if let kindFilter, item.kind != kindFilter {
                return false
            }
            let remaining = item.date.timeIntervalSince(now)
            return remaining > 0 && remaining <= leadSeconds
        }

        return items.map { item in
            let seconds = max(0, Int(item.date.timeIntervalSince(now)))
            if seconds < 60 {
                return "\(item.title) starts in \(seconds)s."
            }
            let minutes = max(1, Int(ceil(Double(seconds) / 60.0)))
            return "\(item.title) starts in \(minutes) minute\(minutes == 1 ? "" : "s")."
        }
    }

    private var shouldShowSilenceButton: Bool {
        guard let activeAlertItem = monitor.activeAlertItem else { return false }
        guard let kindFilter else { return true }
        return activeAlertItem.kind == kindFilter
    }

    private var eventItemsForActions: [UpcomingItem] {
        let allDayItems = monitor.allDayEventItems
        let timedItems = monitor.upcomingItems.filter { $0.kind == .event || $0.kind == .weather }
        let combined = deduplicatedItems((allDayItems + timedItems).sorted { $0.date < $1.date })
        return Array(combined.prefix(max(1, maxListItems)))
    }

    private var reminderItemsForActions: [UpcomingItem] {
        Array(
            deduplicatedItems(monitor.upcomingItems.filter { $0.kind == .reminder })
                .prefix(max(1, maxListItems))
        )
    }

    private var queueItemsForActions: [UpcomingItem] {
        let allDayItems = monitor.allDayEventItems
        let timedItems = monitor.upcomingItems.filter { $0.kind == .event || $0.kind == .weather || $0.kind == .reminder }
        let combined = deduplicatedItems((allDayItems + timedItems).sorted { $0.date < $1.date })
        return Array(combined.prefix(max(1, maxListItems)))
    }

    private func deduplicatedItems(_ items: [UpcomingItem]) -> [UpcomingItem] {
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

    private enum MenuAction {
        case skip
        case complete
    }

    @ViewBuilder
    private func actionRow(item: UpcomingItem, actions: [MenuAction]) -> some View {
        let isHovered = hoveredActionRowKey == item.notificationKey
        ZStack(alignment: .trailing) {
            if item.kind == .reminder {
                Button {
                    monitor.markReminderCompleted(item)
                } label: {
                    rowPrimaryContent(for: item, hideTimeDetails: isHovered)
                }
                .buttonStyle(.plain)
            } else {
                rowPrimaryContent(for: item, hideTimeDetails: isHovered)
            }

            if isHovered {
                HStack(spacing: 4) {
                    if let meetingURL = item.meetingURL {
                        Button {
                            NSWorkspace.shared.open(meetingURL)
                        } label: {
                            actionPill {
                                HStack(spacing: 4) {
                                    Image(systemName: "video.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("Join")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("Join")
                    }

                    ForEach(actions.indices, id: \.self) { index in
                        switch actions[index] {
                        case .skip:
                            Button {
                                monitor.skipItem(item)
                            } label: {
                                actionPill {
                                    Image(systemName: "forward.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .frame(width: 12, height: 12)
                                }
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .help("Skip")
                        case .complete:
                            Button {
                                monitor.markReminderCompleted(item)
                            } label: {
                                actionPill {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .frame(width: 12, height: 12)
                                }
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .help("Complete")
                        }
                    }
                }
                .frame(minWidth: 30, alignment: .trailing)
                .padding(.trailing, 2)
            }
        }
        .font(.caption)
        .padding(.vertical, 0)
        .contentShape(Rectangle())
        .onHover { isHovering in
            hoveredActionRowKey = isHovering ? item.notificationKey : nil
            if item.kind == .reminder {
                hoveredReminderItemID = isHovering ? item.id : nil
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Spacer()
        }
    }

    private func emptySectionRow(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func timeRangeText(for item: UpcomingItem) -> String? {
        guard !item.isAllDay else { return nil }
        let startText = Self.menuTimeFormatter.string(from: item.date)
        guard let endDate = item.endDate, endDate > item.date else {
            return startText
        }
        let endText = Self.menuTimeFormatter.string(from: endDate)
        return "\(startText)-\(endText)"
    }

    @ViewBuilder
    private func actionPill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(height: 18)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                    )
            )
    }

    private func timedDetailText(for item: UpcomingItem) -> String? {
        guard (item.kind == .event || item.kind == .weather), !item.isAllDay else { return nil }
        let now = Date()
        let simplified = true

        guard let endDate = item.endDate, endDate > item.date else {
            if item.date > now {
                return "in \(monitor.relativeCountdown(to: item.date, from: now, simplified: simplified))"
            }
            return monitor.elapsedCountdown(from: item.date, to: now, simplified: simplified) + " ago"
        }

        if item.date <= now, endDate > now {
            let elapsed = monitor.elapsedCountdown(from: item.date, to: now, simplified: simplified)
            let remaining = monitor.relativeCountdown(to: endDate, from: now, simplified: simplified)
            return "\(elapsed) elapsed, \(remaining) left"
        }

        if item.date > now {
            let startsIn = monitor.relativeCountdown(to: item.date, from: now, simplified: simplified)
            let duration = monitor.relativeCountdown(to: endDate, from: item.date, simplified: simplified)
            return "in \(startsIn) for \(duration)"
        }

        let total = monitor.elapsedCountdown(from: item.date, to: endDate, simplified: simplified)
        return "total \(total)"
    }

    private static let menuTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let headerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMM")
        return formatter
    }()

    private func timeText(_ date: Date) -> String {
        Self.menuTimeFormatter.string(from: date)
    }

    private func eventTravelStartDate(for item: UpcomingItem) -> Date? {
        guard let travelMinutes = item.travelTimeMinutes, travelMinutes > 0 else { return nil }
        return item.date.addingTimeInterval(TimeInterval(-travelMinutes * 60))
    }

    private func displayLocationName(from rawLocation: String) -> String {
        let trimmed = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return rawLocation }

        let primary = trimmed
            .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? trimmed

        return primary.isEmpty ? trimmed : primary
    }

    private func shouldShowLocationRow(locationName: String, meetingURL: URL?) -> Bool {
        let normalizedLocation = locationName.lowercased()
        guard !normalizedLocation.isEmpty else { return false }

        // Keep virtual labels/links out of the physical location row.
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

    @ViewBuilder
    private func rowPrimaryContent(for item: UpcomingItem, hideTimeDetails: Bool = false) -> some View {
        let accentColor = Color(nsColor: item.calendarColor)
        let titleColor: Color = .primary
        let detailTextColor: Color = .secondary
        let tertiaryTextColor: Color = .secondary.opacity(0.85)
        let titleFont = Font.system(size: 12, weight: .semibold)
        let detailFont = Font.system(size: 11, weight: .medium)
        let detailIconFont = Font.system(size: 12, weight: .regular)
        let hasVirtualLocation = monitor.isVirtualLocationText(item.locationText)
        let usesEventStyleLayout = item.kind == .event || item.kind == .weather
        let showTravelTime = item.kind == .event
            && !item.isAllDay
            && item.meetingURL == nil
            && !hasVirtualLocation
            && (item.travelTimeMinutes ?? 0) > 0
        let allDayRightLabel = monitor.allDayLabel(for: item)
        let showRightTimeColumn = usesEventStyleLayout && (!item.isAllDay || allDayRightLabel != nil)
        let textBlock = HStack(alignment: .top, spacing: 8) {
            if let markerSymbol = markerSymbolName(for: item) {
                Image(systemName: markerSymbol)
                    .font(.system(size: 12, weight: .regular))
                    .frame(width: 12, height: 12)
                    .foregroundStyle(accentColor)
                    .padding(.top, markerTopPadding(for: item))
            } else if let image = markerImage(for: item) {
                let markerSize = markerImageSize(for: item)
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: markerSize.width, height: markerSize.height)
                    .padding(.top, markerTopPadding(for: item))
            } else {
                Capsule()
                    .fill(Color(nsColor: item.calendarColor))
                    .frame(width: 4)
                    .padding(.vertical, 1)
            }

            if usesEventStyleLayout {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        if showTravelTime, let travelMinutes = item.travelTimeMinutes {
                            HStack(alignment: .center, spacing: 4) {
                                Image(systemName: "car.fill")
                                    .font(detailIconFont)
                                    .frame(width: 12, height: 12, alignment: .center)
                                    .foregroundStyle(accentColor)
                                Text("\(travelMinutes) min travel time")
                                    .font(detailFont)
                                    .foregroundStyle(detailTextColor)
                            }
                        }

                        Text(item.title)
                            .font(titleFont)
                            .foregroundStyle(titleColor)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if item.kind != .weather, let locationText = item.locationText {
                            let locationName = displayLocationName(from: locationText)
                            if shouldShowLocationRow(locationName: locationName, meetingURL: item.meetingURL) {
                                HStack(alignment: .center, spacing: 4) {
                                    Image(systemName: "location.circle")
                                        .font(detailIconFont)
                                        .frame(width: 12, height: 12, alignment: .center)
                                        .foregroundStyle(accentColor)
                                    Text(locationName)
                                        .font(detailFont)
                                        .foregroundStyle(detailTextColor)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        }

                        if let meetingURL = item.meetingURL {
                            HStack(alignment: .center, spacing: 4) {
                                Image(systemName: "video")
                                    .font(detailIconFont)
                                    .frame(width: 12, height: 12, alignment: .center)
                                    .foregroundStyle(accentColor)
                                Text(meetingServiceName(for: meetingURL))
                                    .font(detailFont)
                                    .foregroundStyle(detailTextColor)
                            }
                        }
                    }

                    if showRightTimeColumn && !hideTimeDetails {
                        Spacer(minLength: 6)

                        VStack(alignment: .trailing, spacing: 0) {
                            if showTravelTime, let travelStart = eventTravelStartDate(for: item) {
                                Text(timeText(travelStart))
                                    .font(detailFont)
                                    .foregroundStyle(tertiaryTextColor)
                            }

                            if item.isAllDay {
                                if let allDayRightLabel {
                                    Text(allDayRightLabel)
                                        .font(detailFont)
                                        .foregroundStyle(detailTextColor)
                                }
                            } else {
                                Text(timeText(item.date))
                                    .font(detailFont)
                                    .foregroundStyle(detailTextColor)
                            }

                            if !item.isAllDay, let endDate = item.endDate, endDate > item.date {
                                Text(timeText(endDate))
                                    .font(detailFont)
                                    .foregroundStyle(tertiaryTextColor)
                            }
                        }
                    }
                }
            } else {
                if item.kind == .reminder {
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.title)
                                .font(titleFont)
                                .foregroundStyle(titleColor)

                            if let locationText = item.locationText {
                                let locationName = displayLocationName(from: locationText)
                                if shouldShowLocationRow(locationName: locationName, meetingURL: item.meetingURL) {
                                    HStack(alignment: .center, spacing: 4) {
                                        Image(systemName: "location.circle")
                                            .font(detailIconFont)
                                            .frame(width: 12, height: 12, alignment: .center)
                                            .foregroundStyle(accentColor)
                                        Text(locationName)
                                            .font(detailFont)
                                            .foregroundStyle(detailTextColor)
                                            .lineLimit(2)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }

                            if let meetingURL = item.meetingURL {
                                HStack(alignment: .center, spacing: 4) {
                                    Image(systemName: "video")
                                        .font(detailIconFont)
                                        .frame(width: 12, height: 12, alignment: .center)
                                        .foregroundStyle(accentColor)
                                    Text(meetingServiceName(for: meetingURL))
                                        .font(detailFont)
                                        .foregroundStyle(detailTextColor)
                                }
                            }
                        }

                        Spacer(minLength: 4)

                        if !hideTimeDetails {
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(timeText(item.date))
                                    .font(detailFont)
                                    .foregroundStyle(detailTextColor)
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.title)
                            .font(titleFont)
                            .foregroundStyle(titleColor)

                            if !hideTimeDetails,
                               let detailTime = timeRangeText(for: item) {
                            HStack(alignment: .center, spacing: 4) {
                                Image(systemName: "clock")
                                    .font(detailIconFont)
                                    .frame(width: 12, height: 12, alignment: .center)
                                    .foregroundStyle(accentColor)
                                Text(detailTime)
                                    .font(detailFont)
                                    .foregroundStyle(detailTextColor)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            let now = Date()
            let settings = monitor.snapshotSettings()
            let visual = monitor.segmentBackgroundVisual(for: item, now: now, settings: settings)

            if hoveredActionRowKey == item.notificationKey {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.accentColor.opacity(0.10))
            }

            if visual.color.alphaComponent > 0.01 {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: visual.color).opacity(0.08))
            }
        }
        .overlay(alignment: .leading) {
            let now = Date()
            let settings = monitor.snapshotSettings()
            if let progress = monitor.activeEventProgress(for: item, now: now, settings: settings), progress > 0 {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(nsColor: item.calendarColor).opacity(0.22))
                        .frame(width: max(10, proxy.size.width * progress))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))

        textBlock
    }

    private func markerImage(for item: UpcomingItem) -> NSImage? {
        if item.kind == .reminder {
            return reminderMarkerImage(
                color: item.calendarColor,
                isFilled: hoveredReminderItemID == item.id
            )
        }
        if item.kind == .weather {
            return weatherMarkerImage(for: item.title)
        }
        guard let moment = AstronomyMoment(eventTitle: item.title) else { return nil }
        return astronomyMarkerImage(for: moment)
    }

    private func reminderMarkerImage(color: NSColor, isFilled: Bool) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size)

        if isFilled {
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1.2, dy: 1.2)).fill()
        } else {
            let outerPath = NSBezierPath(ovalIn: rect.insetBy(dx: 0.7, dy: 0.7))
            outerPath.lineWidth = 1.8
            color.setStroke()
            outerPath.stroke()
        }

        return image
    }

    private func markerSymbolName(for item: UpcomingItem) -> String? {
        if monitor.isBirthdayItem(item) {
            return "gift.circle.fill"
        }
        if item.kind == .event, item.isAllDay {
            return "calendar.circle.fill"
        }
        return nil
    }

    private func astronomyMarkerImage(for moment: AstronomyMoment) -> NSImage {
        if let image = AstronomyIconProvider.image(for: moment, pointSize: 13) {
            return image
        }
        return NSImage(size: NSSize(width: 16, height: 12))
    }

    private func weatherMarkerImage(for title: String) -> NSImage {
        let symbolName: String
        switch title.lowercased() {
        case "drizzle":
            symbolName = "cloud.drizzle.fill"
        case "thunderstorm":
            symbolName = "cloud.bolt.rain.fill"
        default:
            symbolName = "cloud.rain.fill"
        }

        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(NSImage.SymbolConfiguration.preferringMulticolor())
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            symbol.isTemplate = false
            return symbol
        }

        return NSImage(size: NSSize(width: 12, height: 12))
    }

    private func markerTopPadding(for item: UpcomingItem) -> CGFloat {
        item.kind == .reminder ? 0 : 2
    }

    private func markerImageSize(for item: UpcomingItem) -> CGSize {
        if AstronomyMoment(eventTitle: item.title) != nil {
            return CGSize(width: 14, height: 14)
        }
        return CGSize(width: 12, height: 12)
    }

    private var contextualActionItems: [UpcomingItem] {
        let candidates = eventItemsForActions.filter { item in
            guard let locationText = locationTextForMenuBarItem(item) else { return false }
            return shouldShowPhysicalMap(for: item, locationText: locationText)
        }
        guard let anchor = candidates.first else { return [] }

        let calendar = Calendar.current
        let concurrent = candidates.filter {
            calendar.isDate($0.date, equalTo: anchor.date, toGranularity: .minute)
        }
        return concurrent.isEmpty ? [anchor] : concurrent
    }

    private func meetingServiceName(for url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        let scheme = (url.scheme ?? "").lowercased()
        let absolute = url.absoluteString.lowercased()

        if host.contains("meet.google.") {
            return "Meet"
        }
        if host.contains("zoom.") || host.contains("us02web.zoom.") {
            return "Zoom"
        }
        if scheme == "msteams"
            || scheme == "microsoftteams"
            || host.contains("teams.")
            || host.contains("teams.microsoft.")
            || host.contains("teams.live.")
            || host.contains("teams.office.")
            || host.contains("aka.ms")
            || host.contains("microsoftteams.")
            || host.contains("teams.ms")
            || absolute.contains("meetup-join")
            || absolute.contains("teams.microsoft.com")
            || absolute.contains("teams.live.com")
            || absolute.contains("teams.office.com") {
            return "Microsoft Teams"
        }
        if host.contains("webex.") {
            return "Webex"
        }
        if host.contains("whereby.") {
            return "Whereby"
        }
        if host.contains("jitsi.") || host.contains("meet.jit.si") {
            return "Jitsi"
        }
        if host.contains("chime.aws") || host.contains("amazonchime.") {
            return "Amazon Chime"
        }

        return "Meeting Link"
    }

    private func mapURL(for locationText: String) -> URL? {
        guard let encoded = locationText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "http://maps.apple.com/?q=\(encoded)")
    }

    private func shouldShowPhysicalMap(for item: UpcomingItem, locationText: String?) -> Bool {
        guard item.meetingURL == nil else { return false }
        guard let locationText else { return false }
        return !monitor.isVirtualLocationText(locationText)
    }

    private func locationTextForMenuBarItem(_ item: UpcomingItem) -> String? {
        if let locationText = item.locationText {
            if monitor.isVirtualLocationText(locationText) {
                return nil
            }
            return locationText
        }

        guard item.kind == .weather else {
            return nil
        }

        let settings = monitor.snapshotSettings()
        guard (-90 ... 90).contains(settings.astronomyLatitude),
              (-180 ... 180).contains(settings.astronomyLongitude) else {
            return nil
        }

        return "\(settings.astronomyLatitude), \(settings.astronomyLongitude)"
    }
}

private struct MiniLocationMapView: View {
    let locationText: String
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 18.4655, longitude: -66.1057),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
    @State private var marker: MapMarkerItem?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Location Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack {
                if let marker {
                    Map(
                        coordinateRegion: $region,
                        annotationItems: [marker]
                    ) { item in
                        MapMarker(coordinate: item.coordinate, tint: .red)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                    Text(isLoading ? "Loading map..." : "Map unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onAppear {
            resolveLocation()
        }
        .onChange(of: locationText) { _ in
            resolveLocation()
        }
    }

    private func resolveLocation() {
        let queries = Self.locationQueries(from: locationText)
        if queries.isEmpty {
            isLoading = false
            marker = nil
            return
        }

        if let parsed = queries.compactMap(Self.parseCoordinatePair).first {
            setMarker(at: parsed)
            return
        }

        isLoading = true
        Self.resolveCoordinate(from: queries, index: 0) { coordinate in
            Task { @MainActor in
                isLoading = false
                guard let coordinate else {
                    marker = nil
                    return
                }
                setMarker(at: coordinate)
            }
        }
    }

    nonisolated private static func resolveCoordinate(
        from queries: [String],
        index: Int,
        completion: @escaping @Sendable (CLLocationCoordinate2D?) -> Void
    ) {
        guard index < queries.count else {
            completion(nil)
            return
        }

        let query = queries[index]
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(query) { placemarks, _ in
            if let coordinate = placemarks?.first?.location?.coordinate {
                completion(coordinate)
                return
            }

            resolveUsingLocalSearch(query) { coordinate in
                if let coordinate {
                    completion(coordinate)
                } else {
                    resolveCoordinate(from: queries, index: index + 1, completion: completion)
                }
            }
        }
    }

    nonisolated private static func resolveUsingLocalSearch(_ query: String, completion: @escaping @Sendable (CLLocationCoordinate2D?) -> Void) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            completion(response?.mapItems.first?.placemark.coordinate)
        }
    }

    private func setMarker(at coordinate: CLLocationCoordinate2D) {
        marker = MapMarkerItem(coordinate: coordinate)
        region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    }

    nonisolated private static func parseCoordinatePair(from text: String) -> CLLocationCoordinate2D? {
        let pattern = #"(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let latRange = Range(match.range(at: 1), in: text),
              let lonRange = Range(match.range(at: 2), in: text),
              let lat = Double(text[latRange]),
              let lon = Double(text[lonRange]),
              (-90 ... 90).contains(lat),
              (-180 ... 180).contains(lon) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    nonisolated private static func locationQueries(from rawText: String) -> [String] {
        let textWithoutLinks = rawText.replacingOccurrences(
            of: #"https?://\S+"#,
            with: "",
            options: .regularExpression
        )
        let cleaned = textWithoutLinks
            .replacingOccurrences(of: "\n", with: ", ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return [] }

        var queries: [String] = []

        func appendIfNeeded(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard !queries.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
            queries.append(trimmed)
        }

        appendIfNeeded(cleaned)

        if let firstLine = rawText
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) {
            appendIfNeeded(firstLine)
        }

        let commaPieces = cleaned
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if commaPieces.count >= 2 {
            appendIfNeeded("\(commaPieces[0]), \(commaPieces[1])")
        }
        if let firstPiece = commaPieces.first {
            appendIfNeeded(firstPiece)
        }

        return queries
    }
}

private struct MapMarkerItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
