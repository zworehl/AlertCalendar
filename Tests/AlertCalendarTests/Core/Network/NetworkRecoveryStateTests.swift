import XCTest
@testable import AlertCalendar

final class NetworkRecoveryStateTests: XCTestCase {
    func testRecoveryFiresOnlyOnUnavailableToAvailableTransition() {
        var state = NetworkRecoveryState()
        XCTAssertFalse(state.observe(isAvailable: true))
        XCTAssertFalse(state.observe(isAvailable: true))
        XCTAssertFalse(state.observe(isAvailable: false))
        XCTAssertFalse(state.observe(isAvailable: false))
        XCTAssertTrue(state.observe(isAvailable: true))
        XCTAssertFalse(state.observe(isAvailable: true))
        XCTAssertFalse(state.observe(isAvailable: false))
        XCTAssertTrue(state.observe(isAvailable: true))
    }

    func testStartingOfflineStillTriggersRecoveryWhenConnectivityArrives() {
        var state = NetworkRecoveryState()
        XCTAssertFalse(state.observe(isAvailable: false))
        XCTAssertTrue(state.observe(isAvailable: true))
    }
}
