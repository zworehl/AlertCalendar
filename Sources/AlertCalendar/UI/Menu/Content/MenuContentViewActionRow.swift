import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    @ViewBuilder
    func actionRow(item: UpcomingItem, actions: [MenuAction]) -> some View {
        MenuContentHoverContainer { isHovered in
            actionRowContent(item: item, actions: actions, isHovered: isHovered)
        }
    }

    @ViewBuilder
    func actionRowContent(item: UpcomingItem, actions: [MenuAction], isHovered: Bool) -> some View {
        let reservedTrailingWidth = isHovered ? hoverActionRowWidth(for: item) : 0
        let now = displayReferenceDate

        ZStack(alignment: .trailing) {
            if item.kind == .reminder {
                Button {
                    monitor.markReminderCompleted(item)
                } label: {
                    rowPrimaryContent(
                        for: item,
                        now: now,
                        isHovered: isHovered,
                        hideTimeDetails: isHovered,
                        reservedTrailingWidth: reservedTrailingWidth
                    )
                }
                .buttonStyle(.plain)
            } else {
                rowPrimaryContent(
                    for: item,
                    now: now,
                    isHovered: isHovered,
                    hideTimeDetails: isHovered,
                    reservedTrailingWidth: reservedTrailingWidth
                )
            }

            if isHovered {
                HStack(spacing: 4) {
                    if let meetingURL = item.meetingURL {
                        joinActionButton(for: meetingURL)
                    }

                    ForEach(actions.indices, id: \.self) { index in
                        switch actions[index] {
                        case .skip:
                            skipActionButton(for: item)
                        case .complete:
                            Button {
                                monitor.markReminderCompleted(item)
                            } label: {
                                reminderCompletionActionLabel(color: Color(nsColor: item.calendarColor.nsColor))
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
    }

    @ViewBuilder
    func rowPrimaryContent(
        for item: UpcomingItem,
        now: Date,
        isHovered: Bool = false,
        hideTimeDetails: Bool = false,
        reservedTrailingWidth: CGFloat = 0
    ) -> some View {
        let accentColor = Color(nsColor: item.calendarColor.nsColor)
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
        let allDayRightLabel = monitor.allDayLabel(
            for: item,
            now: now,
            simplified: settings.useSimplifiedCountdown
        )
        let showRightTimeColumn = usesEventStyleLayout && (!item.isAllDay || allDayRightLabel != nil)
        let textBlock = HStack(alignment: .top, spacing: 8) {
            if let markerSymbol = markerSymbolName(for: item) {
                Image(systemName: markerSymbol)
                    .font(.system(size: 12, weight: .regular))
                    .frame(width: 12, height: 12)
                    .foregroundStyle(accentColor)
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
                                    item.date <= now
                                        ? Self.reminderDueText(
                                            dueDate: item.date,
                                            now: now,
                                            simplified: settings.useSimplifiedCountdown
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
        .padding(.trailing, reservedTrailingWidth)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            let visual = monitor.segmentBackgroundVisual(for: item, now: now, settings: settings)

            if isHovered {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.accentColor.opacity(0.10))
            }

            if visual.color.alphaComponent > 0.01 {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: visual.color).opacity(0.08))
            }
        }
        .overlay(alignment: .leading) {
            if let progress = monitor.activeEventProgress(for: item, now: now, settings: settings), progress > 0 {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(nsColor: item.calendarColor.nsColor).opacity(0.22))
                        .frame(width: max(10, proxy.size.width * progress))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))

        textBlock
    }

}

struct MenuContentHoverContainer<Content: View>: View {
    let content: (Bool) -> Content
    @State private var isHovered = false

    init(@ViewBuilder content: @escaping (Bool) -> Content) {
        self.content = content
    }

    var body: some View {
        content(isHovered)
            .onHover { hovering in
                guard isHovered != hovering else { return }
                isHovered = hovering
            }
    }
}
