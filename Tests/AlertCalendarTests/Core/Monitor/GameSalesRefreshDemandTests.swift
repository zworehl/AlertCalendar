import XCTest
@testable import AlertCalendar

final class GameSalesRefreshDemandTests: XCTestCase {
    func testConcurrentRequestsAreCoalescedWithoutLosingManualOrRecoveryIntent() {
        var demand = GameSalesRefreshDemand()
        demand.merge(GameSalesRefreshDemand(connectivityRestored: true))
        demand.merge(GameSalesRefreshDemand(forceRefresh: true))
        demand.merge(GameSalesRefreshDemand(refreshCalendarState: true))
        demand.merge(GameSalesRefreshDemand())
        XCTAssertTrue(demand.isPending)
        let nextPass = demand.take()
        XCTAssertTrue(nextPass.connectivityRestored)
        XCTAssertTrue(nextPass.forceRefresh)
        XCTAssertTrue(nextPass.refreshCalendarState)
        XCTAssertFalse(demand.isPending)
        demand.merge(GameSalesRefreshDemand(connectivityRestored: true))
        XCTAssertTrue(demand.isPending, "A recovery arriving during the next pass must be retained too")
    }
}
