import Foundation

@MainActor
final class CalendarMonitorRefreshCoordinator {
    private(set) var diagnostics = CalendarMonitorRefreshDiagnostics()
    private(set) var task: Task<Void, Never>?
    private(set) var isRunning = false
    private var hasPendingRefresh = false
    private var pendingReasons: Set<CalendarMonitorRefreshReason> = []
    private var pendingRequestIDs: Set<Int> = []
    private var nextRequestID = 0
    private var lastCompletedRequestID = 0
    private var requestWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    @discardableResult
    func enqueue(
        reason: CalendarMonitorRefreshReason,
        now: @escaping @MainActor () -> Date,
        publishDiagnostics: @escaping @MainActor (CalendarMonitorRefreshDiagnostics) -> Void,
        refresh: @escaping @MainActor (CalendarMonitorRefreshReason) async -> CalendarMonitorRefreshExecutionReport
    ) -> Int {
        enqueueImpl(
            reason: reason,
            now: now,
            publishDiagnostics: publishDiagnostics,
            refresh: { reasons in
                await refresh(Self.primaryReason(from: reasons))
            }
        )
    }

    @discardableResult
    func enqueue(
        reason: CalendarMonitorRefreshReason,
        now: @escaping @MainActor () -> Date,
        publishDiagnostics: @escaping @MainActor (CalendarMonitorRefreshDiagnostics) -> Void,
        refreshReasons: @escaping @MainActor (Set<CalendarMonitorRefreshReason>) async -> CalendarMonitorRefreshExecutionReport
    ) -> Int {
        enqueueImpl(
            reason: reason,
            now: now,
            publishDiagnostics: publishDiagnostics,
            refresh: refreshReasons
        )
    }

    private func enqueueImpl(
        reason: CalendarMonitorRefreshReason,
        now: @escaping @MainActor () -> Date,
        publishDiagnostics: @escaping @MainActor (CalendarMonitorRefreshDiagnostics) -> Void,
        refresh: @escaping @MainActor (Set<CalendarMonitorRefreshReason>) async -> CalendarMonitorRefreshExecutionReport
    ) -> Int {
        nextRequestID += 1
        let requestID = nextRequestID
        pendingRequestIDs.insert(requestID)
        pendingReasons.insert(reason)
        diagnostics.pendingReasons = pendingReasons
        publishDiagnostics(diagnostics)
        hasPendingRefresh = true
        CalendarMonitorLog.refresh.debug("Enqueued refresh: \(reason.rawValue, privacy: .public)")
        guard !isRunning else { return requestID }
        isRunning = true

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                isRunning = false
                task = nil
            }

            while hasPendingRefresh {
                let reasons = pendingReasons
                let requestIDs = pendingRequestIDs
                let reason = Self.primaryReason(from: reasons)
                let startedAt = now()
                hasPendingRefresh = false
                pendingReasons.removeAll()
                pendingRequestIDs.removeAll()
                diagnostics = CalendarMonitorRefreshDiagnostics(
                    lastReason: reason,
                    lastStartedAt: startedAt,
                    lastFinishedAt: nil,
                    lastDuration: nil,
                    pendingReasons: []
                )
                publishDiagnostics(diagnostics)
                CalendarMonitorLog.refresh.info("Starting refresh: \(reason.rawValue, privacy: .public)")

                let report = await refresh(reasons)

                let finishedAt = now()
                diagnostics = CalendarMonitorRefreshDiagnostics(
                    lastReason: reason,
                    lastStartedAt: startedAt,
                    lastFinishedAt: finishedAt,
                    lastDuration: finishedAt.timeIntervalSince(startedAt),
                    pendingReasons: pendingReasons,
                    phaseDurations: report.phaseDurations
                )
                publishDiagnostics(diagnostics)
                completeRequests(requestIDs)
                CalendarMonitorLog.refresh.info(
                    "Finished refresh: \(reason.rawValue, privacy: .public), duration: \(self.diagnostics.lastDuration ?? 0, privacy: .public)"
                )
            }
        }
        return requestID
    }

    func waitForRequest(_ requestID: Int) async {
        guard requestID > lastCompletedRequestID else { return }
        await withCheckedContinuation { continuation in
            requestWaiters[requestID, default: []].append(continuation)
        }
    }

    func waitForCurrentTask() async {
        while let currentTask = task {
            await currentTask.value
        }
    }

    private func completeRequests(_ requestIDs: Set<Int>) {
        guard let maximumRequestID = requestIDs.max() else { return }
        lastCompletedRequestID = max(lastCompletedRequestID, maximumRequestID)
        let completedWaiterIDs = requestWaiters.keys.filter { $0 <= lastCompletedRequestID }
        for requestID in completedWaiterIDs {
            let continuations = requestWaiters.removeValue(forKey: requestID) ?? []
            continuations.forEach { $0.resume() }
        }
    }

    nonisolated static func primaryReason(from reasons: Set<CalendarMonitorRefreshReason>) -> CalendarMonitorRefreshReason {
        for reason in CalendarMonitorRefreshReason.allCases where reasons.contains(reason) {
            return reason
        }
        return .manual
    }
}
