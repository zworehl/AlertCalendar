import Foundation

struct CalendarMonitorGameSalesState {
    var fetchedSales: [GameSaleEvent] = []
    var managedEventRecords: [ManagedGameSaleEventRecord] = []
    var presenceBySaleID: [String: GameSalePresence] = [:]
    var lastRefreshAttemptDate: Date?
    var lastRefreshAttemptFailed = false
}

extension CalendarMonitor {
    var fetchedGameSales: [GameSaleEvent] {
        get { gameSalesState.fetchedSales }
        set { gameSalesState.fetchedSales = newValue }
    }

    var managedGameSaleEventRecords: [ManagedGameSaleEventRecord] {
        get { gameSalesState.managedEventRecords }
        set { gameSalesState.managedEventRecords = newValue }
    }

    var gameSalePresenceByID: [String: GameSalePresence] {
        get { gameSalesState.presenceBySaleID }
        set { gameSalesState.presenceBySaleID = newValue }
    }

    var lastGameSalesRefreshAttemptDate: Date? {
        get { gameSalesState.lastRefreshAttemptDate }
        set { gameSalesState.lastRefreshAttemptDate = newValue }
    }

    var lastGameSalesRefreshAttemptFailed: Bool {
        get { gameSalesState.lastRefreshAttemptFailed }
        set { gameSalesState.lastRefreshAttemptFailed = newValue }
    }
}
