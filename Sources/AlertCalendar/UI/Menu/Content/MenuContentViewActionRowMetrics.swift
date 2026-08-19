import Foundation

extension MenuContentView {
    func actionRowPrimaryTrailingReservation(
        for item: UpcomingItem,
        actions: [MenuAction],
        isHovered: Bool
    ) -> CGFloat {
        guard isHovered else { return 0 }
        return actionRowTrailingReservation(
            for: item,
            actions: actions
        )
    }

    func rowPrimaryContentMinimumHeight(
        for item: UpcomingItem,
        showsTravelTime: Bool,
        showRightTimeColumn: Bool
    ) -> CGFloat {
        if item.footballMatch != nil {
            let rightLineCount = showRightTimeColumn ? 2 : 0
            return Self.dropdownRowMinimumHeight(leftLineCount: 1, rightLineCount: rightLineCount)
        }

        var leftLineCount = 1
        if showsTravelTime {
            leftLineCount += 1
        }

        if !item.isAllDay, let locationText = item.locationText {
            let locationName = displayLocationName(from: locationText)
            if shouldShowLocationRow(locationName: locationName, meetingURL: item.meetingURL) {
                leftLineCount += 1
            }
        }

        if item.meetingURL != nil {
            leftLineCount += 1
        }

        var rightLineCount = 0
        if showRightTimeColumn {
            if showsTravelTime, eventTravelStartDate(for: item) != nil {
                rightLineCount += 1
            }

            rightLineCount += 1

            if !item.isAllDay, let endDate = item.endDate, endDate > item.date {
                rightLineCount += 1
            }
        }

        return Self.dropdownRowMinimumHeight(
            leftLineCount: leftLineCount,
            rightLineCount: rightLineCount
        )
    }

    nonisolated static func shouldPreserveDropdownHoverHeight(for item: UpcomingItem) -> Bool {
        guard item.kind == .event,
              !item.isAllDay,
              let endDate = item.endDate,
              endDate > item.date else {
            return false
        }

        return timedRangeSpansMultipleDays(startDate: item.date, endDate: endDate)
    }

    nonisolated static func dropdownRowMinimumHeight(
        leftLineCount: Int,
        rightLineCount: Int
    ) -> CGFloat {
        let lineCount = max(1, max(leftLineCount, rightLineCount))
        return max(
            MenuMarkerMetrics.singleLineRowMinimumHeight,
            CGFloat(lineCount) * MenuMarkerMetrics.rowLayoutLineHeight
                + MenuMarkerMetrics.rowMinimumVerticalAllowance
        )
    }

    nonisolated static func dropdownCalendarMarkerHeight(
        rowMinimumHeight: CGFloat
    ) -> CGFloat {
        let estimatedLineCount = max(
            1,
            Int(floor(
                (rowMinimumHeight - MenuMarkerMetrics.rowMinimumVerticalAllowance)
                    / MenuMarkerMetrics.rowLayoutLineHeight
            ))
        )
        return MenuMarkerMetrics.calendarMarkerHeight(lineCount: estimatedLineCount)
    }

    nonisolated static func dropdownAccessorySymbolNames(
        _ symbolNames: [String],
        isHovered: Bool
    ) -> [String] {
        isHovered ? [] : symbolNames
    }

    nonisolated static func dropdownAccessorySymbolsTrailingReservation(
        _ symbolNames: [String]
    ) -> CGFloat {
        guard !symbolNames.isEmpty else { return 0 }
        let symbolSpacing: CGFloat = 4
        let leadingSpacing: CGFloat = 8
        return leadingSpacing
            + CGFloat(symbolNames.count) * MenuMarkerMetrics.symbolSize
            + CGFloat(max(0, symbolNames.count - 1)) * symbolSpacing
    }
}
