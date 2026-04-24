import Foundation

@MainActor
final class CalendarMonitorRefreshCoordinator {
    private(set) var diagnostics = CalendarMonitorRefreshDiagnostics()
    private(set) var task: Task<Void, Never>?
    private(set) var isRunning = false
    private var hasPendingRefresh = false
    private var pendingReasons: Set<CalendarMonitorRefreshReason> = []

    func enqueue(
        reason: CalendarMonitorRefreshReason,
        now: @escaping @MainActor () -> Date,
        publishDiagnostics: @escaping @MainActor (CalendarMonitorRefreshDiagnostics) -> Void,
        refresh: @escaping @MainActor (CalendarMonitorRefreshReason) async -> Void
    ) {
        pendingReasons.insert(reason)
        diagnostics.pendingReasons = pendingReasons
        publishDiagnostics(diagnostics)
        hasPendingRefresh = true
        CalendarMonitorLog.refresh.debug("Enqueued refresh: \(reason.rawValue, privacy: .public)")
        guard !isRunning else { return }

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            isRunning = true
            defer {
                isRunning = false
                task = nil
            }

            while hasPendingRefresh {
                let reasons = pendingReasons
                let reason = Self.primaryReason(from: reasons)
                let startedAt = now()
                hasPendingRefresh = false
                pendingReasons.removeAll()
                diagnostics = CalendarMonitorRefreshDiagnostics(
                    lastReason: reason,
                    lastStartedAt: startedAt,
                    lastFinishedAt: nil,
                    lastDuration: nil,
                    pendingReasons: []
                )
                publishDiagnostics(diagnostics)
                CalendarMonitorLog.refresh.info("Starting refresh: \(reason.rawValue, privacy: .public)")

                await refresh(reason)

                let finishedAt = now()
                diagnostics = CalendarMonitorRefreshDiagnostics(
                    lastReason: reason,
                    lastStartedAt: startedAt,
                    lastFinishedAt: finishedAt,
                    lastDuration: finishedAt.timeIntervalSince(startedAt),
                    pendingReasons: pendingReasons
                )
                publishDiagnostics(diagnostics)
                CalendarMonitorLog.refresh.info(
                    "Finished refresh: \(reason.rawValue, privacy: .public), duration: \(self.diagnostics.lastDuration ?? 0, privacy: .public)"
                )
            }
        }
    }

    func waitForCurrentTask() async {
        await task?.value
    }

    static func primaryReason(from reasons: Set<CalendarMonitorRefreshReason>) -> CalendarMonitorRefreshReason {
        for reason in CalendarMonitorRefreshReason.allCases where reasons.contains(reason) {
            return reason
        }
        return .manual
    }
}
