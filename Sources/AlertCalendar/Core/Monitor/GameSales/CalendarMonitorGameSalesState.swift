import Foundation

struct CalendarMonitorGameSalesState {
    var fetchedSales: [GameSaleEvent] = []
    var managedEventRecords: [ManagedGameSaleEventRecord] = []
    var presenceBySaleID: [String: GameSalePresence] = [:]
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

}
