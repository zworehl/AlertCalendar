import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    @ViewBuilder
    func actionRow(item: UpcomingItem, actions: [MenuAction]) -> some View {
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
                                reminderCompletionActionLabel(color: Color(nsColor: item.calendarColor))
                            }
                            .buttonStyle(.plain)
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
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onHover { isHovering in
            hoveredActionRowKey = isHovering ? item.notificationKey : nil
            if item.kind == .reminder {
                hoveredReminderItemID = isHovering ? item.id : nil
            }
        }
    }

    func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Spacer()
        }
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
        guard !item.isAllDay else { return nil }
        let startText = Self.menuTimeFormatter.string(from: item.date)
        guard let endDate = item.endDate, endDate > item.date else {
            return startText
        }
        let endText = Self.menuTimeFormatter.string(from: endDate)
        return "\(startText)-\(endText)"
    }

    @ViewBuilder
    func actionPill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
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

    func reminderCompletionActionLabel(color: Color) -> some View {
        return ZStack {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .fill(Color.primary.opacity(0.08))

            Circle()
                .stroke(color.opacity(0.96), lineWidth: 1.8)
                .padding(1.2)

            Circle()
                .fill(color.opacity(0.98))
                .padding(4.9)
        }
        .frame(width: 18, height: 18)
    }

    static let menuTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    nonisolated static func measuredTextWidth(_ text: String, font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    func timeText(_ date: Date) -> String {
        Self.menuTimeFormatter.string(from: date)
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
    func rowPrimaryContent(for item: UpcomingItem, hideTimeDetails: Bool = false) -> some View {
        let accentColor = Color(nsColor: item.calendarColor)
        let titleColor: Color = .primary
        let detailTextColor: Color = .secondary
        let tertiaryTextColor: Color = .secondary.opacity(0.85)
        let titleFont = Font.system(size: 12, weight: .semibold)
        let detailFont = Font.system(size: 11, weight: .medium)
        let detailIconFont = Font.system(size: 12, weight: .regular)
        let hasVirtualLocation = monitor.isVirtualLocationText(item.locationText)
        let usesEventStyleLayout = item.kind == .event
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
                        if let footballMatch = item.footballMatch {
                            footballEventTextBlock(
                                item: item,
                                match: footballMatch,
                                accentColor: accentColor,
                                titleFont: titleFont,
                                detailFont: detailFont,
                                detailIconFont: detailIconFont,
                                detailTextColor: detailTextColor
                            )
                        } else {
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

                            if !item.isAllDay, let locationText = item.locationText {
                                let locationName = displayLocationName(from: locationText)
                                if shouldShowLocationRow(locationName: locationName, meetingURL: item.meetingURL) {
                                    HStack(alignment: .center, spacing: 4) {
                                        Image(systemName: locationSymbolName(for: item))
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

                            if !item.isAllDay, let locationText = item.locationText {
                                let locationName = displayLocationName(from: locationText)
                                if shouldShowLocationRow(locationName: locationName, meetingURL: item.meetingURL) {
                                    HStack(alignment: .center, spacing: 4) {
                                        Image(systemName: locationSymbolName(for: item))
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
                                Text(
                                    item.date <= Date()
                                        ? Self.reminderDueText(
                                            dueDate: item.date,
                                            now: Date(),
                                            simplified: monitor.snapshotSettings().useSimplifiedCountdown
                                        )
                                        : timeText(item.date)
                                )
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

}
