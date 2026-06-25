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

    nonisolated static func isSlackStatusMeetingItem(_ item: UpcomingItem, calendarID: String? = nil) -> Bool {
        guard item.kind == .event else { return false }
        guard item.isAllDay == false else { return false }
        guard item.showsMutedBackground == false else { return false }
        if let calendarID {
            return item.calendarID == calendarID
        }
        return true
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
        defaultEventDuration: TimeInterval = 60 * 60,
        dynamicStatusRotationInterval: TimeInterval = CalendarMonitorCadence.slackDynamicStatusRotationInterval
    ) -> Date? {
        let relevantCalendarIDs = Set(rules.map(\.calendarID))
        guard !relevantCalendarIDs.isEmpty else { return nil }

        var transitionDates: [Date] = items.compactMap { item -> Date? in
            guard isSlackStatusMeetingItem(item) else { return nil }
            guard let calendarID = item.calendarID else { return nil }
            guard relevantCalendarIDs.contains(calendarID) else { return nil }

            let endDate = slackStatusEndDate(for: item, defaultEventDuration: defaultEventDuration)

            if item.date > now {
                return item.date
            }

            if item.date <= now && endDate > now {
                return endDate
            }

            return nil
        }

        transitionDates.append(
            contentsOf: slackDynamicStatusRotationTransitionDates(
                for: items,
                rules: rules,
                now: now,
                defaultEventDuration: defaultEventDuration,
                dynamicStatusRotationInterval: dynamicStatusRotationInterval
            )
        )

        return transitionDates
            .filter { $0 > now }
            .min()
    }

    nonisolated static func activeSlackRuleStateByConnectionID(
        for items: [UpcomingItem],
        rules: [SlackStatusSyncRule],
        now: Date,
        defaultEventDuration: TimeInterval = 60 * 60,
        dynamicStatusRotationInterval: TimeInterval = CalendarMonitorCadence.slackDynamicStatusRotationInterval
    ) -> [String: SlackActiveRuleState] {
        var activeRuleStateByConnectionID: [String: SlackActiveRuleState] = [:]

        for rule in rules {
            let activeItems = activeSlackStatusMeetingItems(
                for: items,
                calendarID: rule.calendarID,
                now: now,
                defaultEventDuration: defaultEventDuration
            )
            guard !activeItems.isEmpty else {
                continue
            }

            guard let expirationTimestamp = slackMeetingStatusExpirationTimestamp(
                for: activeItems,
                defaultEventDuration: defaultEventDuration
            ) else { continue }
            let statusText = slackStatusText(
                for: rule,
                activeItems: activeItems,
                now: now,
                dynamicStatusRotationInterval: dynamicStatusRotationInterval
            )

            if var existing = activeRuleStateByConnectionID[rule.connectionID] {
                existing = SlackActiveRuleState(
                    statusText: existing.statusText,
                    statusEmoji: existing.statusEmoji,
                    expiration: max(existing.expiration, expirationTimestamp)
                )
                activeRuleStateByConnectionID[rule.connectionID] = existing
            } else {
                activeRuleStateByConnectionID[rule.connectionID] = SlackActiveRuleState(
                    statusText: statusText,
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
        let activeItems = activeSlackStatusMeetingItems(
            for: items,
            calendarID: calendarID,
            now: now,
            defaultEventDuration: defaultEventDuration
        )

        guard !activeItems.isEmpty else { return nil }
        return slackMeetingStatusExpirationTimestamp(
            for: activeItems,
            defaultEventDuration: defaultEventDuration
        )
    }

    nonisolated static func activeSlackStatusMeetingItems(
        for items: [UpcomingItem],
        calendarID: String,
        now: Date,
        defaultEventDuration: TimeInterval = 60 * 60
    ) -> [UpcomingItem] {
        items.filter { item in
            guard isSlackStatusMeetingItem(item, calendarID: calendarID) else { return false }

            let endDate = slackStatusEndDate(for: item, defaultEventDuration: defaultEventDuration)
            return item.date <= now && endDate > now
        }
        .sorted(by: slackStatusItemSort)
    }

    nonisolated static func slackMeetingStatusExpirationTimestamp(
        for activeItems: [UpcomingItem],
        defaultEventDuration: TimeInterval = 60 * 60
    ) -> Int? {
        let latestEndDate = activeItems.compactMap { item in
            slackStatusEndDate(for: item, defaultEventDuration: defaultEventDuration)
        }.max()

        guard let latestEndDate else { return nil }
        return Int(latestEndDate.timeIntervalSince1970.rounded(.down))
    }

    nonisolated static func slackStatusText(
        for rule: SlackStatusSyncRule,
        activeItems: [UpcomingItem],
        now: Date,
        dynamicStatusRotationInterval: TimeInterval = CalendarMonitorCadence.slackDynamicStatusRotationInterval
    ) -> String {
        guard rule.statusTextSource == .eventTitle else {
            return rule.statusText
        }

        guard !activeItems.isEmpty else {
            return rule.statusText
        }

        let index = slackDynamicStatusItemIndex(
            itemCount: activeItems.count,
            now: now,
            dynamicStatusRotationInterval: dynamicStatusRotationInterval
        )
        return activeItems[index].title
    }

    nonisolated static func slackDynamicStatusRotationTransitionDates(
        for items: [UpcomingItem],
        rules: [SlackStatusSyncRule],
        now: Date,
        defaultEventDuration: TimeInterval = 60 * 60,
        dynamicStatusRotationInterval: TimeInterval = CalendarMonitorCadence.slackDynamicStatusRotationInterval
    ) -> [Date] {
        guard dynamicStatusRotationInterval > 0 else { return [] }

        return rules.compactMap { rule in
            guard rule.statusTextSource == .eventTitle else { return nil }

            let activeItems = activeSlackStatusMeetingItems(
                for: items,
                calendarID: rule.calendarID,
                now: now,
                defaultEventDuration: defaultEventDuration
            )
            guard activeItems.count > 1 else { return nil }

            return slackDynamicStatusNextRotationDate(
                now: now,
                dynamicStatusRotationInterval: dynamicStatusRotationInterval
            )
        }
    }

    nonisolated static func slackDynamicStatusNextRotationDate(
        now: Date,
        dynamicStatusRotationInterval: TimeInterval = CalendarMonitorCadence.slackDynamicStatusRotationInterval
    ) -> Date? {
        guard dynamicStatusRotationInterval > 0 else { return nil }

        let elapsed = now.timeIntervalSince1970
        let nextBoundary = (floor(elapsed / dynamicStatusRotationInterval) + 1) * dynamicStatusRotationInterval
        return Date(timeIntervalSince1970: nextBoundary)
    }

    nonisolated static func slackDynamicStatusItemIndex(
        itemCount: Int,
        now: Date,
        dynamicStatusRotationInterval: TimeInterval = CalendarMonitorCadence.slackDynamicStatusRotationInterval
    ) -> Int {
        guard itemCount > 1, dynamicStatusRotationInterval > 0 else { return 0 }

        let bucket = Int(floor(now.timeIntervalSince1970 / dynamicStatusRotationInterval))
        return ((bucket % itemCount) + itemCount) % itemCount
    }

    nonisolated static func slackStatusEndDate(
        for item: UpcomingItem,
        defaultEventDuration: TimeInterval = 60 * 60
    ) -> Date {
        item.endDate ?? item.date.addingTimeInterval(defaultEventDuration)
    }

    nonisolated static func slackStatusItemSort(_ lhs: UpcomingItem, _ rhs: UpcomingItem) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        }

        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }

        return lhs.notificationKey < rhs.notificationKey
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
            guard Self.isSlackStatusMeetingItem(item) else { return false }
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
