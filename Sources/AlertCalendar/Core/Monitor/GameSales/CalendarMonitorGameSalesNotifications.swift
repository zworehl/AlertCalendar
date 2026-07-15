import Foundation

extension CalendarMonitor {
    func prepareGameSaleNotificationAuthorizationIfNeeded() {
        guard defaults.bool(forKey: DefaultsKeys.enableGameSaleAutoAddNotifications) else { return }
        Task {
            await AlertCalendarUserNotifier.requestAuthorizationIfNeeded()
        }
    }

    nonisolated static func gameSaleAutoAddNotificationMessage(
        for sale: GameSaleEvent,
        calendar: Calendar = Calendar.current
    ) -> GameSaleNotificationMessage {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.calendar = calendar
        let inclusiveEnd = calendar.date(byAdding: .day, value: -1, to: sale.endDateExclusive)
            ?? sale.endDateExclusive.addingTimeInterval(-86_400)
        let range = formatter.string(from: sale.startDate, to: inclusiveEnd)

        return GameSaleNotificationMessage(
            title: "Game sale added to Calendar",
            body: "\(sale.store.title): \(sale.title), \(range)."
        )
    }

    nonisolated static func gameSaleAutoAddNotificationKey(for sale: GameSaleEvent) -> String {
        "gameSale.autoAdd.\(sale.id)"
    }

    nonisolated static func gameSaleAutoAddBatchNotificationMessage(
        for sales: [GameSaleEvent]
    ) -> GameSaleNotificationMessage? {
        guard sales.count > 1 else { return nil }
        let names = sales.prefix(3).map(\.title).joined(separator: ", ")
        let remainingCount = sales.count - min(sales.count, 3)
        let suffix = remainingCount > 0 ? " and \(remainingCount) more" : ""
        return GameSaleNotificationMessage(
            title: "\(sales.count) game sales added to Calendar",
            body: "\(names)\(suffix)."
        )
    }

    nonisolated static func gameSaleAutoAddBatchNotificationKey(now: Date) -> String {
        "gameSale.autoAdd.batch.\(Int(now.timeIntervalSince1970))"
    }

    func queueGameSaleAutoAddNotification(for sale: GameSaleEvent) {
        guard defaults.bool(forKey: DefaultsKeys.enableGameSaleAutoAddNotifications) else { return }
        let message = Self.gameSaleAutoAddNotificationMessage(for: sale)
        Task {
            await AlertCalendarUserNotifier.deliver(
                identifier: Self.gameSaleAutoAddNotificationKey(for: sale),
                title: message.title,
                body: message.body
            )
        }
    }

    func queueGameSaleAutoAddNotification(for sales: [GameSaleEvent], now: Date) {
        guard defaults.bool(forKey: DefaultsKeys.enableGameSaleAutoAddNotifications),
              !sales.isEmpty else { return }
        guard sales.count > 1 else {
            queueGameSaleAutoAddNotification(for: sales[0])
            return
        }

        guard let message = Self.gameSaleAutoAddBatchNotificationMessage(for: sales) else { return }
        Task {
            await AlertCalendarUserNotifier.deliver(
                identifier: Self.gameSaleAutoAddBatchNotificationKey(now: now),
                title: message.title,
                body: message.body
            )
        }
    }
}
