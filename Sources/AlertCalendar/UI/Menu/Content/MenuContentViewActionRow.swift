import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    @ViewBuilder
    func actionRow(
        item: UpcomingItem,
        actions: [MenuAction]
    ) -> some View {
        MenuContentHoverContainer { isHovered in
            actionRowContent(
                item: item,
                actions: actions,
                isHovered: isHovered
            )
        }
    }

    @ViewBuilder
    func actionRowContent(
        item: UpcomingItem,
        actions: [MenuAction],
        isHovered: Bool
    ) -> some View {
        let reservedTrailingWidth = actionRowPrimaryTrailingReservation(
            for: item,
            actions: actions,
            isHovered: isHovered
        )
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
                .accessibilityLabel("Complete \(item.title)")
                .help("Complete reminder")
            } else {
                rowPrimaryContent(
                    for: item,
                    now: now,
                    isHovered: isHovered,
                    hideTimeDetails: isHovered,
                    reservedTrailingWidth: reservedTrailingWidth
                )
            }

            MenuActionButtonGroup {
                if item.meetingURL != nil {
                    joinActionButton(for: item)
                }

                ForEach(actions.indices, id: \.self) { index in
                    switch actions[index] {
                    case .skip:
                        skipActionButton(for: item)
                    case .complete:
                        completeActionButton(for: item)
                    }
                }
            }
            .frame(minWidth: MenuActionControlMetrics.minimumHitTargetSize, alignment: .trailing)
            .padding(.trailing, MenuActionControlMetrics.trailingInset)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .accessibilityHidden(!isHovered)
            .disabled(!isHovered)
        }
        .font(.caption)
        .padding(.vertical, 0)
        .frame(minHeight: MenuActionControlMetrics.minimumHitTargetSize, alignment: .center)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
    }

    func actionRowTrailingReservation(
        for item: UpcomingItem,
        actions: [MenuAction]
    ) -> CGFloat {
        hoverActionRowWidth(
            for: item,
            actions: actions
        )
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
        let participationTextOpacity = item.eventParticipationStatus?.appleCalendarTextAlpha ?? 1
        let activeTextureStatus = monitor.activeParticipationTextureStatus(
            for: item,
            now: now,
            settings: settings
        )
        let titleFont = MenuMarkerMetrics.rowTitleFont
        let detailFont = MenuMarkerMetrics.rowDetailFont
        let detailIconFont = Font.system(size: MenuMarkerMetrics.symbolSize, weight: .regular)
        let accessorySymbolNames = Self.dropdownAccessorySymbolNames(
            monitor.menuBarAccessorySymbolNames(for: item),
            isHovered: isHovered
        )
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
        let minimumRowHeight = rowPrimaryContentMinimumHeight(
            for: item,
            showsTravelTime: showTravelTime,
            showRightTimeColumn: showRightTimeColumn
        )
        let textBlock = HStack(alignment: .top, spacing: 8) {
            if let markerSymbol = markerSymbolName(for: item) {
                Image(systemName: markerSymbol)
                    .font(.system(size: MenuMarkerMetrics.symbolSize, weight: .regular))
                    .frame(width: MenuMarkerMetrics.symbolSize, height: MenuMarkerMetrics.symbolSize)
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
                    .frame(
                        width: 4,
                        height: Self.dropdownCalendarMarkerHeight(
                            rowMinimumHeight: minimumRowHeight
                        )
                    )
                    .padding(.top, MenuMarkerMetrics.markerFirstLineTopPadding)
            }

            if usesEventStyleLayout {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let footballMatch = item.footballMatch {
                            footballEventTextBlock(
                                item: item,
                                match: footballMatch,
                                accentColor: accentColor,
                                titleColor: titleColor.opacity(participationTextOpacity),
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
                                        .frame(
                                            width: MenuMarkerMetrics.symbolSize,
                                            height: MenuMarkerMetrics.symbolSize,
                                            alignment: .center
                                        )
                                        .foregroundStyle(accentColor)
                                    Text("\(travelMinutes) min travel time")
                                        .font(detailFont)
                                        .foregroundStyle(detailTextColor)
                                }
                            }

                            titleLine(
                                title: monitor.eventTitle(for: item, inDropdown: true),
                                symbolNames: [],
                                titleFont: titleFont,
                                iconFont: detailIconFont,
                                titleColor: titleColor.opacity(participationTextOpacity),
                                iconColor: detailTextColor.opacity(participationTextOpacity)
                            )

                            if !item.isAllDay, let locationText = item.locationText {
                                let locationName = displayLocationName(from: locationText)
                                if shouldShowLocationRow(locationName: locationName, meetingURL: item.meetingURL) {
                                    HStack(alignment: .center, spacing: 4) {
                                        Image(systemName: locationSymbolName(for: item))
                                            .font(detailIconFont)
                                            .frame(
                                                width: MenuMarkerMetrics.symbolSize,
                                                height: MenuMarkerMetrics.symbolSize,
                                                alignment: .center
                                            )
                                            .foregroundStyle(accentColor)
                                        Text(locationName)
                                            .font(detailFont)
                                            .foregroundStyle(detailTextColor.opacity(participationTextOpacity))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                }
                            }

                            if let meetingURL = item.meetingURL {
                                HStack(alignment: .center, spacing: 4) {
                                    Image(systemName: "video")
                                        .font(detailIconFont)
                                        .frame(
                                            width: MenuMarkerMetrics.symbolSize,
                                            height: MenuMarkerMetrics.symbolSize,
                                            alignment: .center
                                        )
                                        .foregroundStyle(accentColor)
                                    Text(meetingServiceName(for: meetingURL))
                                        .font(detailFont)
                                        .foregroundStyle(detailTextColor.opacity(participationTextOpacity))
                                }
                            }
                        }
                    }
                    .padding(
                        .trailing,
                        Self.dropdownAccessorySymbolsTrailingReservation(accessorySymbolNames)
                    )
                    .overlay(alignment: .trailing) {
                        dropdownAccessorySymbols(
                            symbolNames: accessorySymbolNames,
                            iconFont: detailIconFont,
                            iconColor: detailTextColor.opacity(participationTextOpacity)
                        )
                    }

                    if showRightTimeColumn && !hideTimeDetails {
                        Spacer(minLength: 6)

                        VStack(alignment: .trailing, spacing: 0) {
                            if showTravelTime, let travelStart = eventTravelStartDate(for: item) {
                                Text(timedEventClockText(travelStart, for: item))
                                    .font(detailFont)
                                    .foregroundStyle(tertiaryTextColor)
                                    .lineLimit(1)
                            }

                            if item.isAllDay {
                                if let allDayRightLabel {
                                    Text(allDayRightLabel)
                                        .font(detailFont)
                                        .foregroundStyle(detailTextColor.opacity(participationTextOpacity))
                                        .lineLimit(1)
                                }
                            } else {
                                Text(timedEventClockText(item.date, for: item))
                                    .font(detailFont)
                                    .foregroundStyle(detailTextColor.opacity(participationTextOpacity))
                                    .lineLimit(1)
                            }

                            if !item.isAllDay, let endDate = item.endDate, endDate > item.date {
                                Text(timedEventClockText(endDate, for: item))
                                    .font(detailFont)
                                    .foregroundStyle(tertiaryTextColor.opacity(participationTextOpacity))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.top, MenuMarkerMetrics.detailFirstLineTopPadding)
                    }
                }
            } else {
                if item.kind == .reminder {
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 0) {
                            titleLine(
                                title: monitor.eventTitle(for: item, inDropdown: true),
                                symbolNames: accessorySymbolNames,
                                titleFont: titleFont,
                                iconFont: detailIconFont,
                                titleColor: titleColor,
                                iconColor: detailTextColor
                            )

                            if !item.isAllDay, let locationText = item.locationText {
                                let locationName = displayLocationName(from: locationText)
                                if shouldShowLocationRow(locationName: locationName, meetingURL: item.meetingURL) {
                                    HStack(alignment: .center, spacing: 4) {
                                        Image(systemName: locationSymbolName(for: item))
                                            .font(detailIconFont)
                                            .frame(
                                                width: MenuMarkerMetrics.symbolSize,
                                                height: MenuMarkerMetrics.symbolSize,
                                                alignment: .center
                                            )
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
                                        .frame(
                                            width: MenuMarkerMetrics.symbolSize,
                                            height: MenuMarkerMetrics.symbolSize,
                                            alignment: .center
                                        )
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
                            .padding(.top, MenuMarkerMetrics.detailFirstLineTopPadding)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        titleLine(
                            title: monitor.eventTitle(for: item, inDropdown: true),
                            symbolNames: accessorySymbolNames,
                            titleFont: titleFont,
                            iconFont: detailIconFont,
                            titleColor: titleColor.opacity(participationTextOpacity),
                            iconColor: detailTextColor.opacity(participationTextOpacity)
                        )

                        if !hideTimeDetails,
                           let detailTime = timeRangeText(for: item) {
                            HStack(alignment: .center, spacing: 4) {
                                Image(systemName: "clock")
                                    .font(detailIconFont)
                                    .frame(
                                        width: MenuMarkerMetrics.symbolSize,
                                        height: MenuMarkerMetrics.symbolSize,
                                        alignment: .center
                                    )
                                    .foregroundStyle(accentColor)
                                Text(detailTime)
                                    .font(detailFont)
                                    .foregroundStyle(detailTextColor.opacity(participationTextOpacity))
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, MenuMarkerMetrics.rowContentTopPadding)
        .padding(.bottom, MenuMarkerMetrics.rowContentBottomPadding)
        .padding(.trailing, reservedTrailingWidth)
        .frame(maxWidth: .infinity, minHeight: minimumRowHeight, alignment: .leading)
        .background(alignment: .leading) {
            let visual = monitor.segmentBackgroundVisual(for: item, now: now, settings: settings)

            if isHovered {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
            }

            if visual.color.alphaComponent > 0.01 {
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        Color(nsColor: visual.color)
                            .opacity(activeTextureStatus != nil ? 0.55 : 0.08)
                    )

                if activeTextureStatus != nil {
                    CalendarParticipationTexture(status: activeTextureStatus)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .overlay(alignment: .leading) {
            if let progress = monitor.activeEventProgress(for: item, now: now, settings: settings), progress > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(nsColor: item.calendarColor.nsColor).opacity(0.22))

                        if activeTextureStatus != nil {
                            CalendarParticipationTexture(status: activeTextureStatus)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                    }
                    .frame(width: max(10, proxy.size.width * progress))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))

        textBlock
    }

    @ViewBuilder
    func titleLine(
        title: String,
        symbolNames: [String],
        titleFont: Font,
        iconFont: Font,
        titleColor: Color,
        iconColor: Color
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .font(titleFont)
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)

            if !symbolNames.isEmpty {
                Spacer(minLength: 8)

                dropdownAccessorySymbols(
                    symbolNames: symbolNames,
                    iconFont: iconFont,
                    iconColor: iconColor
                )
                .fixedSize()
                .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func dropdownAccessorySymbols(
        symbolNames: [String],
        iconFont: Font,
        iconColor: Color
    ) -> some View {
        HStack(spacing: 4) {
            ForEach(symbolNames, id: \.self) { symbolName in
                Image(systemName: symbolName)
                    .font(iconFont)
                    .frame(
                        width: MenuMarkerMetrics.symbolSize,
                        height: MenuMarkerMetrics.symbolSize,
                        alignment: .center
                    )
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
            }
        }
    }
}
