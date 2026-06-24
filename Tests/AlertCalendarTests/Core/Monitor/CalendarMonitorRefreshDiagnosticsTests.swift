import XCTest
@testable import AlertCalendar

final class CalendarMonitorRefreshDiagnosticsTests: XCTestCase {
    func testSummaryUsesWaitingTextBeforeFirstRefresh() {
        XCTAssertEqual(
            CalendarMonitorRefreshDiagnostics().summary,
            "Waiting for first refresh..."
        )
    }

    func testSummaryIncludesReasonAndDuration() {
        let diagnostics = CalendarMonitorRefreshDiagnostics(
            lastReason: .eventStoreChanged,
            lastStartedAt: nil,
            lastFinishedAt: nil,
            lastDuration: 1.234,
            pendingReasons: []
        )

        XCTAssertEqual(diagnostics.summary, "Calendar changed - 1.23s")
    }

    func testPendingSummaryUsesReadableReasonTitles() {
        let diagnostics = CalendarMonitorRefreshDiagnostics(
            pendingReasons: [.locationChanged, .manual]
        )

        XCTAssertEqual(diagnostics.pendingSummary, "Location changed, Manual")
    }

    func testManagedFootballSyncPolicySkipsUnrelatedRefreshReasons() {
        XCTAssertTrue(CalendarMonitorRefreshReason.manual.triggersManagedFootballSync)
        XCTAssertTrue(CalendarMonitorRefreshReason.workspaceResumed.triggersManagedFootballSync)
        XCTAssertTrue(CalendarMonitorRefreshReason.footballHeartbeat.triggersManagedFootballSync)
        XCTAssertFalse(CalendarMonitorRefreshReason.locationChanged.triggersManagedFootballSync)
        XCTAssertFalse(CalendarMonitorRefreshReason.itemAction.triggersManagedFootballSync)
        XCTAssertFalse(CalendarMonitorRefreshReason.slackConnectionChanged.triggersManagedFootballSync)
    }
}
