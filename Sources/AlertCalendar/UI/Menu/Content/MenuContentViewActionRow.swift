import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    @ViewBuilder
    func actionRow(
        item: UpcomingItem,
        actions: [MenuAction],
        listPosition: MenuListRowPosition = .only
    ) -> some View {
        MenuContentHoverContainer { isHovered in
            actionRowContent(
                item: item,
                actions: actions,
                isHovered: isHovered,
                listPosition: listPosition
            )
        }
    }

    @ViewBuilder
    func actionRowContent(
        item: UpcomingItem,
        actions: [MenuAction],
        isHovered: Bool,
        listPosition: MenuListRowPosition
    ) -> some View {
        let reservedTrailingWidth = actionRowPrimaryTrailingReservation(
            for: item,
            actions: actions,
            isHovered: isHovered
        )
        let now = displayReferenceDate

        ZStack(alignment: .trailing) {
            rowPrimaryContent(
                for: item,
                now: now,
                isHovered: isHovered,
                hideTimeDetails: isHovered,
                reservedTrailingWidth: reservedTrailingWidth,
                listPosition: listPosition
            )

            MenuActionButtonGroup {
                if item.meetingURL != nil {
                    joinActionButton(for: item)
                }
                if shouldShowOpenLinkAction(for: item) {
                    openLinkActionButton(for: item)
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
        reservedTrailingWidth: CGFloat = 0,
        listPosition: MenuListRowPosition = .only
    ) -> some View {
        let accentColor = Color(nsColor: item.calendarColor.nsColor)
        let titleColor: Color = .primary
        let detailTextColor: Color = .secondary
        let tertiaryTextColor: Color = .secondary.opacity(0.85)
        let participationTextOpacity = item.eventParticipationStatus?.appleCalendarStyle.textAlpha ?? 1
        let participationTextureStatus = monitor.participationTextureStatus(for: item)
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
        let rowShape = MenuListRowBackgroundShape(position: listPosition, cornerRadius: 7)
        let textBlock = HStack(alignment: .top, spacing: 8) {
            menuMarkerColumn(
                for: item,
                isHovered: isHovered,
                rowMinimumHeight: minimumRowHeight,
                allowsReminderCompletion: true
            )

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
                                title: dropdownVisibleTitle(for: item),
                                originalTitle: item.title,
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

                            linkDetailRow(
                                for: item,
                                detailFont: detailFont,
                                accentColor: accentColor,
                                detailTextColor: detailTextColor.opacity(participationTextOpacity),
                                isHovered: isHovered
                            )
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
                                title: dropdownVisibleTitle(for: item),
                                originalTitle: item.title,
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

                            linkDetailRow(
                                for: item,
                                detailFont: detailFont,
                                accentColor: accentColor,
                                detailTextColor: detailTextColor,
                                isHovered: isHovered
                            )
                        }

                        Spacer(minLength: 4)

                        if !hideTimeDetails {
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(Self.reminderScheduleText(
                                    for: item,
                                    now: now,
                                    simplified: settings.useSimplifiedCountdown,
                                    timedText: timeText(item.date)
                                ))
                                    .font(detailFont)
                                    .foregroundStyle(detailTextColor)
                            }
                            .padding(.top, MenuMarkerMetrics.detailFirstLineTopPadding)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        titleLine(
                            title: dropdownVisibleTitle(for: item),
                                originalTitle: item.title,
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
                rowShape
                    .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
            }

            if visual.color.alphaComponent > 0.01 {
                rowShape
                    .fill(
                        Color(nsColor: visual.color)
                            .opacity(participationTextureStatus != nil ? 0.55 : 0.08)
                    )

                if participationTextureStatus != nil {
                    CalendarParticipationTexture(status: participationTextureStatus)
                        .clipShape(rowShape)
                }
            }
        }
        .overlay(alignment: .leading) {
            if let progress = monitor.activeEventProgress(for: item, now: now, settings: settings), progress > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        rowShape
                            .fill(Color(nsColor: item.calendarColor.nsColor).opacity(0.22))

                        if participationTextureStatus != nil {
                            CalendarParticipationTexture(status: participationTextureStatus)
                                .clipShape(rowShape)
                        }
                    }
                    .frame(width: max(10, proxy.size.width * progress))
                }
            }
        }
        .clipShape(MenuListRowBackgroundShape(position: listPosition, cornerRadius: 7))
        // Keep the active-event progress fill composited inside the row while
        // the menu's scroll view and window resize during dismissal.
        .compositingGroup()

        textBlock
    }

    @ViewBuilder
    func titleLine(
        title: String,
        originalTitle: String? = nil,
        symbolNames: [String],
        titleFont: Font,
        iconFont: Font,
        titleColor: Color,
        iconColor: Color
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .help(originalTitle ?? title)
                .accessibilityLabel(originalTitle ?? title)
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

    func dropdownVisibleTitle(for item: UpcomingItem) -> String {
        monitor.eventTitle(for: item, inDropdown: true)
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
