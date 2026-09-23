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
        let maximumLeadMinutes = rules
            .filter(\.startsBeforeEvent)
            .map(\.leadMinutes)
            .max() ?? 0
        let endDate = now.addingTimeInterval(
            Double(lookAheadHours) * 3600 + Double(maximumLeadMinutes) * 60
        )
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
        enabledRules: [SlackStatusSyncRule],
        playback: AppleMusicPlayback? = nil,
        musicExpirationTimestamp: Int? = nil
    ) -> [SlackStatusSyncTarget] {
        let connectionsByID = Dictionary(uniqueKeysWithValues: settings.slackConnections.map { ($0.id, $0) })
        let musicSettings = settings.appleMusicStatus.normalized(validConnectionIDs: Set(connectionsByID.keys))
        let musicConnectionIDs = musicSettings.isEnabled ? musicSettings.connectionIDs : []
        let enabledConnectionIDs = Set(enabledRules.map(\.connectionID)).union(musicConnectionIDs)
        let activeRuleStateByConnectionID = Self.activeSlackRuleStateByConnectionID(
            for: items,
            rules: enabledRules,
            now: now
        )

        let relevantConnectionIDs = Set(slackManagedStateByConnectionID.keys).union(enabledConnectionIDs)
        return relevantConnectionIDs.compactMap { connectionID in
            guard let connection = connectionsByID[connectionID] else { return nil }

            if let playback, musicConnectionIDs.contains(connectionID),
               Self.shouldUseAppleMusicStatus(
                   musicPriority: musicSettings.priority,
                   calendarPriority: activeRuleStateByConnectionID[connectionID]?.priority
               ) {
                return SlackStatusSyncTarget(
                    connection: connection,
                    mode: .meeting(snapshot: SlackProfileStatusSnapshot(
                        statusText: playback.statusText,
                        statusEmoji: playback.statusEmoji,
                        statusExpiration: musicExpirationTimestamp ?? playback.expirationTimestamp(now: now)
                    ))
                )
            }

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

    nonisolated static func shouldUseAppleMusicStatus(musicPriority: Int, calendarPriority: Int?) -> Bool {
        guard let calendarPriority else { return true }
        return musicPriority < calendarPriority
    }

    nonisolated static func nextSlackStatusSyncTransitionDate(
        for items: [UpcomingItem],
        rules: [SlackStatusSyncRule],
        now: Date,
        defaultEventDuration: TimeInterval = 60 * 60,
        dynamicStatusRotationInterval: TimeInterval = CalendarMonitorCadence.slackDynamicStatusRotationInterval
    ) -> Date? {
        guard !rules.isEmpty else { return nil }

        var transitionDates: [Date] = []
        for rule in rules {
            for item in items {
                guard isSlackStatusMeetingItem(item, calendarID: rule.calendarID) else { continue }

                let endDate = slackStatusEndDate(for: item, defaultEventDuration: defaultEventDuration)
                guard endDate > now else { continue }

                if item.date > now {
                    if rule.startsBeforeEvent {
                        let leadDate = slackStatusLeadDate(for: item, rule: rule)
                        if leadDate > now {
                            transitionDates.append(leadDate)
                        }
                    }
                    transitionDates.append(item.date)
                } else {
                    transitionDates.append(endDate)
                }
            }
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
        var candidatesByConnectionID: [String: [SlackRuleStateCandidate]] = [:]

        for (priority, rule) in rules.enumerated() {
            let activeItems = activeSlackStatusMeetingItems(
                for: items,
                calendarID: rule.calendarID,
                now: now,
                defaultEventDuration: defaultEventDuration
            )
            let upcomingItems = upcomingSlackStatusMeetingItems(
                for: items,
                rule: rule,
                now: now,
                defaultEventDuration: defaultEventDuration
            )
            let displayItems = activeItems.isEmpty ? upcomingItems : activeItems
            guard !displayItems.isEmpty else { continue }

            let managedItems = activeItems + upcomingItems
            let phase: SlackRuleActivityPhase = activeItems.isEmpty ? .upcoming : .active

            guard let expirationTimestamp = slackMeetingStatusExpirationTimestamp(
                for: managedItems,
                defaultEventDuration: defaultEventDuration
            ) else { continue }
            let statusText = phase == .upcoming
                ? rule.preEventStatusText
                : slackStatusText(
                    for: rule,
                    activeItems: displayItems,
                    now: now,
                    dynamicStatusRotationInterval: dynamicStatusRotationInterval
                )

            candidatesByConnectionID[rule.connectionID, default: []].append(
                SlackRuleStateCandidate(
                    priority: rule.priority,
                    order: priority,
                    phase: phase,
                    statusText: statusText,
                    statusEmoji: phase == .upcoming ? rule.preEventStatusEmoji : rule.statusEmoji,
                    expiration: expirationTimestamp
                )
            )
        }

        return candidatesByConnectionID.reduce(into: [:]) { result, entry in
            let candidates = entry.value
            guard let selectedCandidate = candidates.max(by: { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                if lhs.phase != rhs.phase {
                    return lhs.phase.rawValue < rhs.phase.rawValue
                }
                return lhs.order > rhs.order
            }) else {
                return
            }

            result[entry.key] = SlackActiveRuleState(
                statusText: selectedCandidate.statusText,
                statusEmoji: selectedCandidate.statusEmoji,
                expiration: candidates.map(\.expiration).max() ?? selectedCandidate.expiration,
                priority: selectedCandidate.priority
            )
        }
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

    nonisolated static func upcomingSlackStatusMeetingItems(
        for items: [UpcomingItem],
        rule: SlackStatusSyncRule,
        now: Date,
        defaultEventDuration: TimeInterval = 60 * 60
    ) -> [UpcomingItem] {
        guard rule.startsBeforeEvent else { return [] }

        return items.filter { item in
            guard isSlackStatusMeetingItem(item, calendarID: rule.calendarID) else { return false }
            guard item.date > now else { return false }

            let endDate = slackStatusEndDate(for: item, defaultEventDuration: defaultEventDuration)
            guard endDate > now else { return false }
            return slackStatusLeadDate(for: item, rule: rule) <= now
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

    nonisolated static func slackStatusLeadDate(
        for item: UpcomingItem,
        rule: SlackStatusSyncRule
    ) -> Date {
        item.date.addingTimeInterval(-Double(rule.leadMinutes) * 60)
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

}
