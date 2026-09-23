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

    func testOnlyManualRefreshForcesExternalFeeds() {
        XCTAssertTrue(CalendarMonitorRefreshReason.manual.forcesExternalFeedRefresh)
        XCTAssertFalse(CalendarMonitorRefreshReason.launch.forcesExternalFeedRefresh)
        XCTAssertFalse(CalendarMonitorRefreshReason.periodic.forcesExternalFeedRefresh)
        XCTAssertFalse(CalendarMonitorRefreshReason.footballHeartbeat.forcesExternalFeedRefresh)
    }

    func testCalendarSyncUsesLightweightCalendarOnlyRefresh() {
        XCTAssertTrue(CalendarMonitorRefreshReason.calendarSync.refreshesCalendarStateOnly)
        XCTAssertFalse(CalendarMonitorRefreshReason.calendarSync.triggersManagedFootballSync)
        XCTAssertFalse(CalendarMonitorRefreshReason.calendarSync.triggersFootballAutoAddSync)
        XCTAssertFalse(CalendarMonitorRefreshReason.calendarSync.forcesExternalFeedRefresh)
        XCTAssertEqual(CalendarMonitorRefreshReason.calendarSync.title, "Calendar sync")
        XCTAssertEqual(CalendarMonitorCadence.calendarStateRefreshInterval, 10 * 60)
        XCTAssertEqual(CalendarMonitorCadence.maximumHeartbeatInterval, 60)
    }

    func testInitialSnapshotAndReminderCompletionStayOnLocalLane() {
        for reason in [CalendarMonitorRefreshReason.launchSnapshot, .launchConfirmation, .remindersChanged] {
            XCTAssertTrue(reason.refreshesCalendarStateOnly)
            XCTAssertFalse(reason.triggersManagedFootballSync)
            XCTAssertFalse(reason.triggersFootballAutoAddSync)
            XCTAssertFalse(reason.evaluatesGameSales)
            XCTAssertFalse(reason.evaluatesGoogleHolidays)
        }
        XCTAssertTrue(CalendarMonitorRefreshReason.launchSnapshot.schedulesReminderFetch)
        XCTAssertFalse(CalendarMonitorRefreshReason.launchConfirmation.schedulesReminderFetch)
        XCTAssertFalse(CalendarMonitorRefreshReason.remindersChanged.schedulesReminderFetch)
    }

    func testUnrelatedLocalReasonsSkipExternalFeedLanes() {
        for reason in [
            CalendarMonitorRefreshReason.locationChanged,
            .calendarSelectionChanged,
            .itemAction,
            .slackConnectionChanged,
            .eventStoreChanged,
        ] {
            XCTAssertFalse(reason.evaluatesGameSales)
            XCTAssertFalse(reason.evaluatesGoogleHolidays)
        }
        XCTAssertFalse(CalendarMonitorRefreshReason.eventStoreChanged.triggersManagedFootballSync)
    }

    func testDiagnosticsSummarizeMeasuredPhases() {
        let diagnostics = CalendarMonitorRefreshDiagnostics(
            phaseDurations: ["Calendar snapshot": 0.25, "Football": 1.5]
        )
        XCTAssertEqual(diagnostics.phasesSummary, "Calendar snapshot 0.25s, Football 1.50s")
    }
}
