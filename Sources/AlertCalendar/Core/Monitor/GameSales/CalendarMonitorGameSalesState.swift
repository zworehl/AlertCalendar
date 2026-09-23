import Foundation

struct GameSalesRefreshDemand: Equatable {
    var forceRefresh = false
    var refreshCalendarState = false
    var connectivityRestored = false

    var isPending: Bool { forceRefresh || refreshCalendarState || connectivityRestored }

    mutating func merge(_ demand: Self) {
        forceRefresh = forceRefresh || demand.forceRefresh
        refreshCalendarState = refreshCalendarState || demand.refreshCalendarState
        connectivityRestored = connectivityRestored || demand.connectivityRestored
    }

    mutating func take() -> Self {
        defer { self = Self() }
        return self
    }
}

struct CalendarMonitorGameSalesState {
    var fetchedSales: [GameSaleEvent] = []
    var managedEventRecords: [ManagedGameSaleEventRecord] = []
    var presenceBySaleID: [String: GameSalePresence] = [:]
    var lastRefreshAttemptDate: Date?
    var lastRefreshAttemptFailed = false
    var connectivityObserver: NetworkRecoveryObserver?
    var refreshDemand = GameSalesRefreshDemand()
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
