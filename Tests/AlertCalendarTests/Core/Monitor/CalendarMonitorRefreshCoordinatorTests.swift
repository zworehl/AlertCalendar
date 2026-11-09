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
        XCTAssertEqual(
            CalendarMonitorRefreshCoordinator.primaryReason(from: [.calendarSync, .eventStoreChanged]),
            .eventStoreChanged
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
                return CalendarMonitorRefreshExecutionReport(
                    phaseDurations: ["Calendar snapshot": 0.25]
                )
            }
        )

        await coordinator.waitForCurrentTask()

        XCTAssertEqual(refreshReasons, [.manual])
        XCTAssertEqual(diagnostics.first?.pendingReasons, [.manual])
        XCTAssertEqual(diagnostics.last?.lastReason, .manual)
        XCTAssertEqual(diagnostics.last?.lastDuration, 1)
        XCTAssertEqual(diagnostics.last?.phaseDurations["Calendar snapshot"], 0.25)
    }

    func testWaitingForCurrentTaskDrainsRefreshQueuedDuringLaunch() async {
        let coordinator = CalendarMonitorRefreshCoordinator()
        var refreshReasons: [CalendarMonitorRefreshReason] = []
        let now = Date(timeIntervalSince1970: 100)

        coordinator.enqueue(
            reason: .launch,
            now: { now },
            publishDiagnostics: { _ in },
            refresh: { reason in
                refreshReasons.append(reason)
                guard reason == .launch else { return CalendarMonitorRefreshExecutionReport() }

                coordinator.enqueue(
                    reason: .calendarSync,
                    now: { now },
                    publishDiagnostics: { _ in },
                    refresh: { _ in
                        XCTFail("The running coordinator must retain its original refresh operation.")
                        return CalendarMonitorRefreshExecutionReport()
                    }
                )
                return CalendarMonitorRefreshExecutionReport()
            }
        )

        await coordinator.waitForCurrentTask()

        XCTAssertEqual(refreshReasons, [.launch, .calendarSync])
        XCTAssertFalse(coordinator.isRunning)
    }

    func testWaitingForRequestDoesNotWaitForWorkQueuedAfterIt() async {
        let coordinator = CalendarMonitorRefreshCoordinator()
        let now = Date(timeIntervalSince1970: 100)
        var completedReasons: [CalendarMonitorRefreshReason] = []
        var releaseBackground: CheckedContinuation<Void, Never>?

        let launchID = coordinator.enqueue(
            reason: .launchSnapshot,
            now: { now },
            publishDiagnostics: { _ in },
            refresh: { reason in
                if reason == .launchSnapshot {
                    coordinator.enqueue(
                        reason: .launch,
                        now: { now },
                        publishDiagnostics: { _ in },
                        refresh: { _ in CalendarMonitorRefreshExecutionReport() }
                    )
                } else if reason == .launch {
                    await withCheckedContinuation { releaseBackground = $0 }
                }
                completedReasons.append(reason)
                return CalendarMonitorRefreshExecutionReport()
            }
        )

        await coordinator.waitForRequest(launchID)

        XCTAssertEqual(completedReasons, [.launchSnapshot])
        while releaseBackground == nil {
            await Task.yield()
        }
        releaseBackground?.resume()
        await coordinator.waitForCurrentTask()
        XCTAssertEqual(completedReasons, [.launchSnapshot, .launch])
    }
}
