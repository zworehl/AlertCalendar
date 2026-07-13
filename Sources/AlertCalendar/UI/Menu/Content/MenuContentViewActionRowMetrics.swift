import Foundation

extension MenuContentView {
    func rowPrimaryContentMinimumHeight(
        for item: UpcomingItem,
        showsTravelTime: Bool,
        showRightTimeColumn: Bool
    ) -> CGFloat? {
        guard Self.shouldPreserveDropdownHoverHeight(for: item) else {
            return nil
        }

        if item.footballMatch != nil {
            let rightLineCount = showRightTimeColumn ? 2 : 0
            guard rightLineCount > 1 else { return nil }
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

            if let endDate = item.endDate, endDate > item.date {
                rightLineCount += 1
            }
        }

        guard rightLineCount > 1 else { return nil }
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
        return max(34, CGFloat(lineCount) * 16 + 12)
    }

    nonisolated static func dropdownAccessorySymbolNames(
        _ symbolNames: [String],
        isHovered: Bool
    ) -> [String] {
        isHovered ? [] : symbolNames
    }
}
