import Foundation

extension UpcomingItem {
    var isDateOnlyReminder: Bool {
        kind == .reminder && !hasExplicitTime
    }

    nonisolated static func sortPrecedes(
        _ left: UpcomingItem,
        _ right: UpcomingItem
    ) -> Bool {
        let calendar = Calendar.autoupdatingCurrent
        let leftDay = calendar.startOfDay(for: left.date)
        let rightDay = calendar.startOfDay(for: right.date)

        if leftDay != rightDay {
            return leftDay < rightDay
        }

        if left.isDateOnlyReminder != right.isDateOnlyReminder {
            return !left.isDateOnlyReminder
        }

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
}
