import Foundation

extension CalendarMonitor {
    func updateSlackRuntimeStatusDescription(
        now: Date,
        rules: [SlackStatusSyncRule],
        items: [UpcomingItem],
        nextTransitionDate: Date?
    ) {
        guard !rules.isEmpty else {
            slackRuntimeStatusDescription = nil
            return
        }

        let uniqueCalendarCount = Set(rules.map(\.calendarID)).count
        let activeItems = items.filter { item in
            guard Self.isSlackStatusMeetingItem(item) else { return false }
            let endDate = item.endDate ?? item.date.addingTimeInterval(60 * 60)
            return item.date <= now && endDate > now
        }
        let preEventItemKeys = Set(
            rules.flatMap { rule in
                Self.upcomingSlackStatusMeetingItems(
                    for: items,
                    rule: rule,
                    now: now
                )
                .map(\.notificationKey)
            }
        )
        let rulesText = rules.count == 1 ? "1 rule" : "\(rules.count) rules"
        let calendarsText = uniqueCalendarCount == 1 ? "1 calendar" : "\(uniqueCalendarCount) calendars"

        if !activeItems.isEmpty {
            let activeText = activeItems.count == 1 ? "1 active meeting" : "\(activeItems.count) active meetings"
            if let nextTransitionDate {
                slackRuntimeStatusDescription =
                    "Watching \(rulesText) across \(calendarsText). \(activeText). Next change: \(Self.slackRuntimeDateFormatter.string(from: nextTransitionDate))."
            } else {
                slackRuntimeStatusDescription =
                    "Watching \(rulesText) across \(calendarsText). \(activeText)."
            }
            return
        }

        if !preEventItemKeys.isEmpty {
            let preEventText = preEventItemKeys.count == 1
                ? "1 meeting is in its pre-event window"
                : "\(preEventItemKeys.count) meetings are in their pre-event window"
            if let nextTransitionDate {
                slackRuntimeStatusDescription =
                    "Watching \(rulesText) across \(calendarsText). \(preEventText). Next change: \(Self.slackRuntimeDateFormatter.string(from: nextTransitionDate))."
            } else {
                slackRuntimeStatusDescription =
                    "Watching \(rulesText) across \(calendarsText). \(preEventText)."
            }
            return
        }

        if let nextTransitionDate {
            slackRuntimeStatusDescription =
                "Watching \(rulesText) across \(calendarsText). No active meetings right now. Next change: \(Self.slackRuntimeDateFormatter.string(from: nextTransitionDate))."
            return
        }

        slackRuntimeStatusDescription =
            "Watching \(rulesText) across \(calendarsText). No active or upcoming meetings were found in the current window."
    }

    func scheduleSlackStatusSync(now: Date, settings: AppSettings) {
        let enabledRules = enabledSlackStatusSyncRules(in: settings)
        let items = slackRelevantItems(now: now, settings: settings, rules: enabledRules)
        let targets = slackStatusSyncTargets(
            now: now,
            settings: settings,
            items: items,
            enabledRules: enabledRules
        )
        let nextTransitionDate = Self.nextSlackStatusSyncTransitionDate(
            for: items,
            rules: enabledRules,
            now: now
        )
        updateSlackRuntimeStatusDescription(
            now: now,
            rules: enabledRules,
            items: items,
            nextTransitionDate: nextTransitionDate
        )
        appendSlackDiagnosticsLog(
            "schedule rules=\(enabledRules.count) items=\(items.count) managed=\(managedSlackItemTitles(from: items, rules: enabledRules, now: now)) next=\(formattedSlackTransitionDate(nextTransitionDate))"
        )
        scheduleNextSlackStatusSyncTransition(at: nextTransitionDate, now: now)

        let targetsChanged = targets != slackQueuedTargets
        if targetsChanged {
            slackQueuedTargets = targets
            slackStatusSyncNeedsAnotherPass = true
        }

        if settings.appleMusicStatus.isEnabled && !settings.appleMusicStatus.connectionIDs.isEmpty {
            slackStatusSyncNeedsAnotherPass = true
        }

        cancelStaleSlackStatusSyncTaskIfNeeded(now: now)

        if slackStatusSyncErrorDescription != nil {
            slackStatusSyncNeedsAnotherPass = true
        }

        guard Self.shouldStartSlackStatusSyncTask(
            hasRunningTask: slackStatusSyncTask != nil,
            needsAnotherPass: slackStatusSyncNeedsAnotherPass
        ) else { return }

        startSlackStatusSyncTask(now: now)
    }

    nonisolated static func shouldStartSlackStatusSyncTask(
        hasRunningTask: Bool,
        needsAnotherPass: Bool
    ) -> Bool {
        !hasRunningTask && needsAnotherPass
    }

    nonisolated static func slackStatusSyncTaskTimedOut(
        startedAt: Date?,
        now: Date,
        timeout: TimeInterval = CalendarMonitorCadence.slackStatusSyncTaskTimeoutInterval
    ) -> Bool {
        guard startedAt != nil else { return false }
        return CalendarMonitorTime.hasElapsed(since: startedAt, now: now, interval: timeout)
    }

    func cancelStaleSlackStatusSyncTaskIfNeeded(now: Date) {
        guard slackStatusSyncTask != nil else { return }
        guard Self.slackStatusSyncTaskTimedOut(
            startedAt: slackStatusSyncTaskStartedAt,
            now: now,
            timeout: Self.slackStatusSyncTaskTimeoutInterval
        ) else { return }

        appendSlackDiagnosticsLog(
            "apply-timeout started=\(formattedSlackTransitionDate(slackStatusSyncTaskStartedAt)) timeout=\(Self.slackStatusSyncTaskTimeoutInterval)s"
        )
        slackStatusSyncTask?.cancel()
        slackStatusSyncTask = nil
        slackStatusSyncTaskStartedAt = nil
        slackStatusSyncRunID = nil
        slackStatusSyncNeedsAnotherPass = true
        slackStatusSyncErrorDescription = "Slack sync timed out. AlertCalendar will retry."
    }

    func startSlackStatusSyncTask(now: Date) {
        guard slackStatusSyncTask == nil else { return }

        let runID = UUID()
        slackStatusSyncRunID = runID
        slackStatusSyncTaskStartedAt = now
        slackStatusSyncTask = Task { [weak self] in
            guard let self else { return }
            await self.processSlackStatusSyncQueue(runID: runID)
        }
    }

    func requestSlackStatusSyncEvaluation(now: Date, settings: AppSettings) {
        lastSlackStatusSyncEvaluationDate = now
        scheduleSlackStatusSync(now: now, settings: settings)
    }

    func evaluateSlackStatusSyncOnHeartbeatIfNeeded(now: Date, settings: AppSettings) {
        guard shouldEvaluateSlackStatusSyncOnHeartbeat(now: now, settings: settings) else { return }
        requestSlackStatusSyncEvaluation(now: now, settings: settings)
    }

    func shouldEvaluateSlackStatusSyncOnHeartbeat(now: Date, settings: AppSettings) -> Bool {
        let enabledRules = enabledSlackStatusSyncRules(in: settings)
        let hasRelevantSlackWork = !enabledRules.isEmpty ||
            (settings.appleMusicStatus.isEnabled && !settings.appleMusicStatus.connectionIDs.isEmpty) ||
            !slackManagedStateByConnectionID.isEmpty
        guard hasRelevantSlackWork else { return false }

        let interval = settings.appleMusicStatus.isEnabled && !settings.appleMusicStatus.connectionIDs.isEmpty
            ? CalendarMonitorCadence.appleMusicStatusHeartbeatInterval
            : Self.slackStatusSyncHeartbeatEvaluationInterval
        return CalendarMonitorTime.hasElapsed(
            since: lastSlackStatusSyncEvaluationDate,
            now: now,
            interval: interval
        )
    }

    func scheduleNextSlackStatusSyncTransition(at transitionDate: Date?, now: Date) {
        if slackScheduledTransitionDate == transitionDate, slackStatusSyncTransitionTask != nil {
            return
        }

        slackStatusSyncTransitionTask?.cancel()
        slackStatusSyncTransitionTask = nil
        slackScheduledTransitionDate = transitionDate

        guard let transitionDate else { return }

        let nanoseconds = CalendarMonitorTime.nanoseconds(until: transitionDate, now: now)

        slackStatusSyncTransitionTask = Task { [weak self] in
            guard let self else { return }

            if nanoseconds > 0 {
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled else { return }
            guard self.slackScheduledTransitionDate == transitionDate else { return }

            self.slackScheduledTransitionDate = nil
            self.slackStatusSyncTransitionTask = nil

            let currentNow = self.fixedSecondNow()
            let currentSettings = self.snapshotSettings()
            self.requestSlackStatusSyncEvaluation(now: currentNow, settings: currentSettings)
        }
    }
}
