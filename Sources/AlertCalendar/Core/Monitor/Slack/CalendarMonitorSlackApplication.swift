import Foundation

extension CalendarMonitor {
    func processSlackStatusSyncQueue(runID: UUID) async {
        while slackStatusSyncNeedsAnotherPass,
              slackStatusSyncRunID == runID,
              !Task.isCancelled {
            slackStatusSyncNeedsAnotherPass = false
            await applySlackStatusSyncTargets(slackQueuedTargets)
        }

        guard slackStatusSyncRunID == runID else { return }
        slackStatusSyncTask = nil
        slackStatusSyncTaskStartedAt = nil
        slackStatusSyncRunID = nil
    }

    func applySlackStatusSyncTargets(_ targets: [SlackStatusSyncTarget]) async {
        var errorMessages: [String] = []
        appendSlackDiagnosticsLog("apply-start targets=\(targets.count) \(describeSlackTargets(targets))")

        for target in targets {
            do {
                switch target.mode {
                case .clear:
                    if slackManagedStateByConnectionID[target.connection.id] != nil {
                        try await restoreSlackStatusIfNeeded(for: target.connection)
                        appendSlackDiagnosticsLog("apply-clear success connection=\(target.connection.displayLabel)")
                    } else {
                        appendSlackDiagnosticsLog("apply-clear skipped connection=\(target.connection.displayLabel) reason=no-managed-state")
                    }
                case let .meeting(snapshot):
                    try await applyMeetingStatusIfNeeded(
                        for: target.connection,
                        snapshot: snapshot
                    )
                    appendSlackDiagnosticsLog(
                        "apply-meeting success connection=\(target.connection.displayLabel) text=\(snapshot.statusText) emoji=\(snapshot.statusEmoji) expiration=\(snapshot.statusExpiration)"
                    )
                }
            } catch {
                appendSlackDiagnosticsLog("apply-error connection=\(target.connection.displayLabel) error=\(error.localizedDescription)")
                errorMessages.append("\(target.connection.displayLabel): \(error.localizedDescription)")
            }
        }

        if errorMessages.isEmpty {
            slackStatusSyncErrorDescription = nil
            lastSlackStatusSyncDate = fixedSecondNow()
        } else {
            slackStatusSyncErrorDescription = errorMessages.joined(separator: " ")
        }
    }

    func applyMeetingStatusIfNeeded(
        for connection: SlackConnection,
        snapshot: SlackProfileStatusSnapshot
    ) async throws {
        var state = slackManagedStateByConnectionID[connection.id] ?? SlackManagedStatusState()

        if state.requestedStatus == snapshot {
            return
        }

        if state.previousStatus == nil {
            let currentStatus = try await slackClient.currentProfileStatus(for: connection)
            let currentStatusLooksCalendarManaged = SlackMeetingStatus.isLikelyManaged(
                currentStatus,
                matching: snapshot.identity
            )
            if !SlackMeetingStatus.isManaged(currentStatus, managedSnapshot: state.managedStatus),
               !currentStatusLooksCalendarManaged {
                state.previousStatus = currentStatus
            }
        }

        let appliedSnapshot = try await slackClient.setStatus(snapshot, for: connection)
        state.requestedStatus = snapshot
        state.managedStatus = appliedSnapshot
        slackManagedStateByConnectionID[connection.id] = state
    }

    func restoreSlackStatusIfNeeded(for connection: SlackConnection) async throws {
        var state = slackManagedStateByConnectionID[connection.id] ?? SlackManagedStatusState()
        let currentStatus = try await slackClient.currentProfileStatus(for: connection)

        if SlackMeetingStatus.isManaged(currentStatus, managedSnapshot: state.managedStatus) {
            let restoredStatus = Self.slackRestoredStatus(from: state)
            _ = try await slackClient.setStatus(restoredStatus, for: connection)
        }

        state.previousStatus = nil
        state.requestedStatus = nil
        state.managedStatus = nil
        if state.previousStatus == nil, state.requestedStatus == nil, state.managedStatus == nil {
            slackManagedStateByConnectionID.removeValue(forKey: connection.id)
        } else {
            slackManagedStateByConnectionID[connection.id] = state
        }
    }

    nonisolated static func slackRestoredStatus(from state: SlackManagedStatusState) -> SlackProfileStatusSnapshot {
        let emptyStatus = SlackProfileStatusSnapshot(
            statusText: "",
            statusEmoji: "",
            statusExpiration: 0
        )

        guard let previousStatus = state.previousStatus else { return emptyStatus }
        guard let managedStatus = state.managedStatus else { return previousStatus }

        if SlackMeetingStatus.isLikelyManaged(previousStatus, matching: managedStatus.identity) {
            return emptyStatus
        }

        return previousStatus
    }
}
