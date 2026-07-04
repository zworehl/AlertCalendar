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

    func testIsInProgressTracksPendingAndRunningRefreshes() {
        XCTAssertFalse(CalendarMonitorRefreshDiagnostics().isInProgress)

        XCTAssertTrue(
            CalendarMonitorRefreshDiagnostics(
                pendingReasons: [.manual]
            ).isInProgress
        )

        XCTAssertTrue(
            CalendarMonitorRefreshDiagnostics(
                lastReason: .manual,
                lastStartedAt: Date(timeIntervalSince1970: 1_720_000_000),
                lastFinishedAt: nil,
                lastDuration: nil,
                pendingReasons: []
            ).isInProgress
        )

        XCTAssertFalse(
            CalendarMonitorRefreshDiagnostics(
                lastReason: .manual,
                lastStartedAt: Date(timeIntervalSince1970: 1_720_000_000),
                lastFinishedAt: Date(timeIntervalSince1970: 1_720_000_001),
                lastDuration: 1,
                pendingReasons: []
            ).isInProgress
        )
    }

    func testManagedFootballSyncPolicySkipsUnrelatedRefreshReasons() {
        XCTAssertTrue(CalendarMonitorRefreshReason.manual.triggersManagedFootballSync)
        XCTAssertTrue(CalendarMonitorRefreshReason.workspaceResumed.triggersManagedFootballSync)
        XCTAssertTrue(CalendarMonitorRefreshReason.footballHeartbeat.triggersManagedFootballSync)
        XCTAssertFalse(CalendarMonitorRefreshReason.locationChanged.triggersManagedFootballSync)
        XCTAssertFalse(CalendarMonitorRefreshReason.itemAction.triggersManagedFootballSync)
        XCTAssertFalse(CalendarMonitorRefreshReason.slackConnectionChanged.triggersManagedFootballSync)
    }

    func testFootballAutoAddSyncPolicySkipsInternalCalendarActions() {
        XCTAssertTrue(CalendarMonitorRefreshReason.launch.triggersFootballAutoAddSync)
        XCTAssertTrue(CalendarMonitorRefreshReason.periodic.triggersFootballAutoAddSync)
        XCTAssertTrue(CalendarMonitorRefreshReason.settingsChanged.triggersFootballAutoAddSync)
        XCTAssertFalse(CalendarMonitorRefreshReason.footballCalendarAction.triggersFootballAutoAddSync)
        XCTAssertFalse(CalendarMonitorRefreshReason.eventStoreChanged.triggersFootballAutoAddSync)
        XCTAssertFalse(CalendarMonitorRefreshReason.itemAction.triggersFootballAutoAddSync)
    }
}
