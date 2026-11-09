import Foundation

extension CalendarMonitor {
    static let appleMusicTransientFailureTolerance: TimeInterval = 15

    func processSlackStatusSyncQueue(runID: UUID) async {
        while slackStatusSyncNeedsAnotherPass,
              slackStatusSyncRunID == runID,
              !Task.isCancelled {
            slackStatusSyncNeedsAnotherPass = false
            let settings = snapshotSettings()
            let musicEnabled = settings.appleMusicStatus.isEnabled &&
                !settings.appleMusicStatus.connectionIDs.isEmpty
            let musicObservation = musicEnabled
                ? await MusicPlaybackReader.currentPlaybackObservation(
                    source: settings.appleMusicStatus.source
                )
                : .stopped
            guard slackStatusSyncRunID == runID, !Task.isCancelled else { break }
            recordSlackStatusSyncProgress(runID: runID)
            let now = fixedSecondNow()
            let playback = resolvedAppleMusicPlayback(
                observation: musicObservation,
                now: now
            )
            let musicExpirationTimestamp = resolvedAppleMusicExpirationTimestamp(
                playback: playback,
                now: now
            )
            let rules = enabledSlackStatusSyncRules(in: settings)
            let items = slackRelevantItems(now: now, settings: settings, rules: rules)
            let targets = slackStatusSyncTargets(
                now: now,
                settings: settings,
                items: items,
                enabledRules: rules,
                playback: playback,
                musicExpirationTimestamp: musicExpirationTimestamp
            )
            await applySlackStatusSyncTargets(targets, runID: runID)
            guard slackStatusSyncRunID == runID, !Task.isCancelled else { break }
            if musicObservation == .unavailable {
                appendSlackDiagnosticsLog("music-observation unavailable source=\(settings.appleMusicStatus.source.rawValue)")
                if slackStatusSyncErrorDescription == nil {
                    slackStatusSyncErrorDescription = L10n.text("Could not read music playback. AlertCalendar will retry.")
                }
            }
        }

        guard slackStatusSyncRunID == runID else { return }
        slackStatusSyncTask = nil
        slackStatusSyncTaskStartedAt = nil
        slackRuntimeState.statusSyncLastProgressAt = nil
        slackStatusSyncRunID = nil
    }

    func resolvedAppleMusicPlayback(
        observation: AppleMusicPlaybackObservation,
        now: Date
    ) -> AppleMusicPlayback? {
        switch observation {
        case let .playing(playback):
            slackRuntimeState.appleMusicLastPlayback = playback
            slackRuntimeState.appleMusicLastSuccessfulObservationAt = now
            return playback
        case .stopped:
            slackRuntimeState.appleMusicLastPlayback = nil
            slackRuntimeState.appleMusicLastSuccessfulObservationAt = nil
            return nil
        case .unavailable:
            guard let playback = slackRuntimeState.appleMusicLastPlayback,
                  let observedAt = slackRuntimeState.appleMusicLastSuccessfulObservationAt else {
                return nil
            }
            let elapsed = now.timeIntervalSince(observedAt)
            guard elapsed >= 0, elapsed <= Self.appleMusicTransientFailureTolerance else {
                slackRuntimeState.appleMusicLastPlayback = nil
                slackRuntimeState.appleMusicLastSuccessfulObservationAt = nil
                return nil
            }
            return playback.projected(after: elapsed)
        }
    }

    func resolvedAppleMusicExpirationTimestamp(
        playback: AppleMusicPlayback?,
        now: Date
    ) -> Int? {
        guard let playback else {
            slackRuntimeState.appleMusicTrackID = nil
            slackRuntimeState.appleMusicExpirationTimestamp = nil
            slackRuntimeState.appleMusicElapsedDuration = nil
            slackRuntimeState.appleMusicObservedAt = nil
            return nil
        }

        let expectedProgress = slackRuntimeState.appleMusicObservedAt.map { now.timeIntervalSince($0) }
        let observedProgress = slackRuntimeState.appleMusicElapsedDuration.map {
            playback.elapsedDuration - $0
        }
        let playbackContinuedNormally: Bool
        if let expectedProgress, let observedProgress {
            playbackContinuedNormally = abs(expectedProgress - observedProgress) < 2
        } else {
            playbackContinuedNormally = false
        }

        if slackRuntimeState.appleMusicTrackID == playback.cacheIdentity,
           playbackContinuedNormally,
           let expiration = slackRuntimeState.appleMusicExpirationTimestamp,
           expiration > Int(now.timeIntervalSince1970),
           !playback.shouldRenewExpiration(expiration, now: now) {
            slackRuntimeState.appleMusicElapsedDuration = playback.elapsedDuration
            slackRuntimeState.appleMusicObservedAt = now
            return expiration
        }

        let expiration = playback.expirationTimestamp(now: now)
        slackRuntimeState.appleMusicTrackID = playback.cacheIdentity
        slackRuntimeState.appleMusicExpirationTimestamp = expiration
        slackRuntimeState.appleMusicElapsedDuration = playback.elapsedDuration
        slackRuntimeState.appleMusicObservedAt = now
        return expiration
    }

    func recordSlackStatusSyncProgress(runID: UUID?) {
        guard let runID, slackStatusSyncRunID == runID, !Task.isCancelled else { return }
        slackRuntimeState.statusSyncLastProgressAt = fixedSecondNow()
    }

    func applySlackStatusSyncTargets(_ targets: [SlackStatusSyncTarget], runID: UUID) async {
        var errorMessages: [String] = []
        appendSlackDiagnosticsLog("apply-start targets=\(targets.count) \(describeSlackTargets(targets))")

        for target in targets {
            guard isSlackApplicationRunning, !Task.isCancelled else { return }
            do {
                switch target.mode {
                case .clear:
                    if slackManagedStateByConnectionID[target.connection.id] != nil {
                        try await restoreSlackStatusIfNeeded(for: target.connection, runID: runID)
                        try Task.checkCancellation()
                        appendSlackDiagnosticsLog("apply-clear success connection=\(target.connection.displayLabel)")
                    } else {
                        appendSlackDiagnosticsLog("apply-clear skipped connection=\(target.connection.displayLabel) reason=no-managed-state")
                    }
                case let .meeting(snapshot):
                    try await applyMeetingStatusIfNeeded(
                        for: target.connection,
                        snapshot: snapshot,
                        runID: runID
                    )
                    try Task.checkCancellation()
                    appendSlackDiagnosticsLog(
                        "apply-meeting success connection=\(target.connection.displayLabel) text=\(snapshot.statusText) emoji=\(snapshot.statusEmoji) expiration=\(snapshot.statusExpiration)"
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                appendSlackDiagnosticsLog("apply-error connection=\(target.connection.displayLabel) error=\(error.localizedDescription)")
                errorMessages.append("\(target.connection.displayLabel): \(AlertCalendarLanguage.errorMessage(error))")
            }
        }

        guard slackStatusSyncRunID == runID, isSlackApplicationRunning, !Task.isCancelled else { return }
        if errorMessages.isEmpty {
            slackStatusSyncErrorDescription = nil
            lastSlackStatusSyncDate = fixedSecondNow()
        } else {
            slackStatusSyncErrorDescription = errorMessages.joined(separator: " ")
        }
    }

    func applyMeetingStatusIfNeeded(
        for connection: SlackConnection,
        snapshot: SlackProfileStatusSnapshot,
        runID: UUID? = nil
    ) async throws {
        var state = slackManagedStateByConnectionID[connection.id] ?? SlackManagedStatusState()

        if state.requestedStatus == snapshot {
            let currentStatus = try await slackClient.currentProfileStatus(for: connection)
            recordSlackStatusSyncProgress(runID: runID)
            guard isSlackApplicationRunning, !Task.isCancelled else { return }
            if SlackMeetingStatus.isManaged(currentStatus, managedSnapshot: state.managedStatus) {
                return
            }
        }

        if state.previousStatus == nil {
            let currentStatus = try await slackClient.currentProfileStatus(for: connection)
            recordSlackStatusSyncProgress(runID: runID)
            try Task.checkCancellation()
            let currentStatusLooksCalendarManaged = SlackMeetingStatus.isLikelyManaged(
                currentStatus,
                matching: snapshot.identity
            )
            if !SlackMeetingStatus.isManaged(currentStatus, managedSnapshot: state.managedStatus),
               !currentStatusLooksCalendarManaged {
                state.previousStatus = currentStatus
            }
        }

        guard isSlackApplicationRunning, !Task.isCancelled else { return }
        let appliedSnapshot = try await slackClient.setStatus(snapshot, for: connection)
        try Task.checkCancellation()
        recordSlackStatusSyncProgress(runID: runID)
        state.requestedStatus = snapshot
        state.managedStatus = appliedSnapshot
        slackManagedStateByConnectionID[connection.id] = state
    }

    func restoreSlackStatusIfNeeded(for connection: SlackConnection, runID: UUID? = nil) async throws {
        var state = slackManagedStateByConnectionID[connection.id] ?? SlackManagedStatusState()
        let currentStatus = try await slackClient.currentProfileStatus(for: connection)
        recordSlackStatusSyncProgress(runID: runID)

        guard isSlackApplicationRunning, !Task.isCancelled else { return }
        if SlackMeetingStatus.isManaged(currentStatus, managedSnapshot: state.managedStatus) {
            let restoredStatus = Self.slackRestoredStatus(from: state)
            _ = try await slackClient.setStatus(restoredStatus, for: connection)
            try Task.checkCancellation()
            recordSlackStatusSyncProgress(runID: runID)
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
