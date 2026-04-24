import Foundation

extension CalendarMonitor {
    func enabledSlackStatusSyncRules(in settings: AppSettings) -> [SlackStatusSyncRule] {
        SlackStatusSyncRule.normalized(
            settings.slackStatusSyncRules.filter(\.isEnabled),
            validConnectionIDs: Set(settings.slackConnections.map(\.id)),
            validCalendarIDs: Set(availableEventCalendars.map(\.id))
        )
    }

    func slackRelevantItems(
        now: Date,
        settings: AppSettings,
        rules: [SlackStatusSyncRule]
    ) -> [UpcomingItem] {
        guard hasEventsAccess else { return [] }

        let relevantCalendarIDs = Set(rules.map(\.calendarID))
        guard !relevantCalendarIDs.isEmpty else { return [] }

        let relevantCalendars = eventStore.calendars(for: .event)
            .filter { relevantCalendarIDs.contains($0.calendarIdentifier) }
        guard !relevantCalendars.isEmpty else { return [] }

        let lookAheadHours = max(
            settings.lookAheadHours,
            Int(ceil(Double(settings.menuBarRotationWindowMinutes) / 60.0))
        )
        let endDate = now.addingTimeInterval(Double(lookAheadHours) * 3600)
        let lookBackHours = max(24, lookAheadHours)
        let startDate = now.addingTimeInterval(-Double(lookBackHours) * 3600)
        let events = loadEvents(from: startDate, to: endDate, now: now, calendars: relevantCalendars)

        return Self.visibleSlackStatusItems(
            from: deduplicatedItemsByNotificationKey(events.timedItems),
            skippedItemKeys: skippedItemKeys
        )
    }

    nonisolated static func visibleSlackStatusItems(
        from items: [UpcomingItem],
        skippedItemKeys: Set<String>
    ) -> [UpcomingItem] {
        items.filter { !skippedItemKeys.contains($0.notificationKey) }
    }

    func slackStatusSyncTargets(
        now: Date,
        settings: AppSettings,
        items: [UpcomingItem],
        enabledRules: [SlackStatusSyncRule]
    ) -> [SlackStatusSyncTarget] {
        let connectionsByID = Dictionary(uniqueKeysWithValues: settings.slackConnections.map { ($0.id, $0) })
        let enabledConnectionIDs = Set(enabledRules.map(\.connectionID))
        let activeRuleStateByConnectionID = Self.activeSlackRuleStateByConnectionID(
            for: items,
            rules: enabledRules,
            now: now
        )

        let relevantConnectionIDs = Set(slackManagedStateByConnectionID.keys).union(enabledConnectionIDs)
        return relevantConnectionIDs.compactMap { connectionID in
            guard let connection = connectionsByID[connectionID] else { return nil }

            if let activeRuleState = activeRuleStateByConnectionID[connectionID] {
                return SlackStatusSyncTarget(
                    connection: connection,
                    mode: .meeting(
                        snapshot: SlackMeetingStatus.snapshot(
                            text: activeRuleState.statusText,
                            emoji: activeRuleState.statusEmoji,
                            expirationTimestamp: activeRuleState.expiration
                        )
                    )
                )
            }

            return SlackStatusSyncTarget(connection: connection, mode: .clear)
        }
        .sorted { lhs, rhs in
            let teamOrder = lhs.connection.teamName.localizedCaseInsensitiveCompare(rhs.connection.teamName)
            if teamOrder != .orderedSame {
                return teamOrder == .orderedAscending
            }
            return lhs.connection.displayLabel.localizedCaseInsensitiveCompare(rhs.connection.displayLabel) == .orderedAscending
        }
    }

    nonisolated static func nextSlackStatusSyncTransitionDate(
        for items: [UpcomingItem],
        rules: [SlackStatusSyncRule],
        now: Date,
        defaultEventDuration: TimeInterval = 60 * 60
    ) -> Date? {
        let relevantCalendarIDs = Set(rules.map(\.calendarID))
        guard !relevantCalendarIDs.isEmpty else { return nil }

        return items.compactMap { item in
            guard item.kind == .event else { return nil }
            guard item.isAllDay == false else { return nil }
            guard let calendarID = item.calendarID else { return nil }
            guard relevantCalendarIDs.contains(calendarID) else { return nil }

            let endDate = item.endDate ?? item.date.addingTimeInterval(defaultEventDuration)

            if item.date > now {
                return item.date
            }

            if item.date <= now && endDate > now {
                return endDate
            }

            return nil
        }
        .filter { $0 > now }
        .min()
    }

    nonisolated static func activeSlackRuleStateByConnectionID(
        for items: [UpcomingItem],
        rules: [SlackStatusSyncRule],
        now: Date,
        defaultEventDuration: TimeInterval = 60 * 60
    ) -> [String: SlackActiveRuleState] {
        var activeRuleStateByConnectionID: [String: SlackActiveRuleState] = [:]

        for rule in rules {
            guard let expirationTimestamp = slackMeetingStatusExpirationTimestamp(
                for: items,
                calendarID: rule.calendarID,
                now: now,
                defaultEventDuration: defaultEventDuration
            ) else {
                continue
            }

            if var existing = activeRuleStateByConnectionID[rule.connectionID] {
                existing = SlackActiveRuleState(
                    statusText: existing.statusText,
                    statusEmoji: existing.statusEmoji,
                    expiration: max(existing.expiration, expirationTimestamp)
                )
                activeRuleStateByConnectionID[rule.connectionID] = existing
            } else {
                activeRuleStateByConnectionID[rule.connectionID] = SlackActiveRuleState(
                    statusText: rule.statusText,
                    statusEmoji: rule.statusEmoji,
                    expiration: expirationTimestamp
                )
            }
        }

        return activeRuleStateByConnectionID
    }

    nonisolated static func slackMeetingStatusExpirationTimestamp(
        for items: [UpcomingItem],
        calendarID: String,
        now: Date,
        defaultEventDuration: TimeInterval = 60 * 60
    ) -> Int? {
        let activeItems = items.filter { item in
            guard item.kind == .event else { return false }
            guard item.isAllDay == false else { return false }
            guard item.calendarID == calendarID else { return false }

            let endDate = item.endDate ?? item.date.addingTimeInterval(defaultEventDuration)
            return item.date <= now && endDate > now
        }

        let latestEndDate = activeItems.compactMap { item in
            item.endDate ?? item.date.addingTimeInterval(defaultEventDuration)
        }.max()

        guard let latestEndDate else { return nil }
        return Int(latestEndDate.timeIntervalSince1970.rounded(.down))
    }

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
            guard item.kind == .event, item.isAllDay == false else { return false }
            let endDate = item.endDate ?? item.date.addingTimeInterval(60 * 60)
            return item.date <= now && endDate > now
        }
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
            "schedule rules=\(enabledRules.count) items=\(items.count) active=\(activeSlackItemTitles(from: items, now: now)) next=\(formattedSlackTransitionDate(nextTransitionDate))"
        )
        scheduleNextSlackStatusSyncTransition(at: nextTransitionDate, now: now)
        guard targets != slackQueuedTargets || slackStatusSyncTask == nil else { return }

        slackQueuedTargets = targets
        slackStatusSyncNeedsAnotherPass = true
        guard slackStatusSyncTask == nil else { return }

        slackStatusSyncTask = Task { [weak self] in
            guard let self else { return }
            await self.processSlackStatusSyncQueue()
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
        let hasRelevantSlackWork = !enabledRules.isEmpty || !slackManagedStateByConnectionID.isEmpty
        guard hasRelevantSlackWork else { return false }

        return CalendarMonitorTime.hasElapsed(
            since: lastSlackStatusSyncEvaluationDate,
            now: now,
            interval: Self.slackStatusSyncHeartbeatEvaluationInterval
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
