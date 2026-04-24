import Foundation
import XCTest
@testable import AlertCalendar

@MainActor
final class CalendarMonitorRefreshCoordinatorTests: XCTestCase {
    func testPrimaryReasonUsesRefreshReasonPriority() {
        XCTAssertEqual(
            CalendarMonitorRefreshCoordinator.primaryReason(from: [.manual, .eventStoreChanged]),
            .manual
        )
        XCTAssertEqual(
            CalendarMonitorRefreshCoordinator.primaryReason(from: [.locationChanged, .footballHeartbeat]),
            .footballHeartbeat
        )
    }

    func testEnqueuePublishesPendingAndCompletedDiagnostics() async {
        let coordinator = CalendarMonitorRefreshCoordinator()
        var diagnostics: [CalendarMonitorRefreshDiagnostics] = []
        var refreshReasons: [CalendarMonitorRefreshReason] = []
        var now = Date(timeIntervalSince1970: 100)

        coordinator.enqueue(
            reason: .manual,
            now: { now },
            publishDiagnostics: { diagnostics.append($0) },
            refresh: { reason in
                refreshReasons.append(reason)
                now = Date(timeIntervalSince1970: 101)
            }
        )

        await coordinator.waitForCurrentTask()

        XCTAssertEqual(refreshReasons, [.manual])
        XCTAssertEqual(diagnostics.first?.pendingReasons, [.manual])
        XCTAssertEqual(diagnostics.last?.lastReason, .manual)
        XCTAssertEqual(diagnostics.last?.lastDuration, 1)
    }
}
