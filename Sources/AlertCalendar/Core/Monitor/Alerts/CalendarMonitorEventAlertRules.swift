import EventKit
import Foundation

struct CalendarAlertRuleApplicationResult {
    var updatedCount = 0
    var failureCount = 0
    var commitFailed = false

    mutating func merge(_ other: CalendarAlertRuleApplicationResult) {
        updatedCount += other.updatedCount
        failureCount += other.failureCount
        commitFailed = commitFailed || other.commitFailed
    }
}

extension CalendarMonitor {
    nonisolated static let calendarAlertRuleSyncBuffer: TimeInterval = 7 * 24 * 60 * 60
    nonisolated static let maximumCalendarAlertRuleSyncHorizon: TimeInterval = 372 * 24 * 60 * 60

    func applyCalendarAlertRules(
        now: Date,
        settings: AppSettings,
        reason: CalendarMonitorRefreshReason
    ) {
        guard hasEventsAccess else { return }

        let enabledRules = CalendarAlertRule.normalized(settings.calendarAlertRules)
            .filter { $0.isEnabled && settings.selectedEventCalendarIDs.contains($0.calendarID) }
        guard !enabledRules.isEmpty else {
            cancelCompleteCalendarAlertRuleSync(clearStoredFingerprint: true)
            return
        }

        let rulesByCalendarID = Dictionary(
            uniqueKeysWithValues: enabledRules.map { ($0.calendarID, $0) }
        )
        let calendars = eventStore.calendars(for: .event).filter { calendar in
            rulesByCalendarID[calendar.calendarIdentifier] != nil
                && calendar.allowsContentModifications
                && calendar.type != .subscription
                && calendar.type != .birthday
        }
        guard !calendars.isEmpty else { return }

        let incrementalWindow = CalendarAlertRuleScanWindow(
            start: now.addingTimeInterval(-60),
            end: Self.calendarAlertRuleSyncEndDate(
                now: now,
                rules: enabledRules,
                lookAheadHours: settings.lookAheadHours
            )
        )
        var processedEventKeys: Set<String> = []
        let result = applyCalendarAlertRules(
            in: incrementalWindow,
            rulesByCalendarID: rulesByCalendarID,
            calendars: calendars,
            processedEventKeys: &processedEventKeys
        )
        publishCalendarAlertRuleResult(result)
        scheduleCompleteCalendarAlertRuleSync(
            enabledRules: enabledRules,
            rulesByCalendarID: rulesByCalendarID,
            calendars: calendars,
            force: false
        )
    }

    func applyCalendarAlertRules(
        in window: CalendarAlertRuleScanWindow,
        rulesByCalendarID: [String: CalendarAlertRule],
        calendars: [EKCalendar],
        processedEventKeys: inout Set<String>,
        includesRecurringSeries: Bool = true
    ) -> CalendarAlertRuleApplicationResult {
        let predicate = eventStore.predicateForEvents(
            withStart: window.start,
            end: window.end,
            calendars: calendars
        )
        let events = eventStore.events(matching: predicate).sorted {
            $0.startDate < $1.startDate
        }
        var result = CalendarAlertRuleApplicationResult()

        for event in events {
            guard
                let rule = rulesByCalendarID[event.calendar.calendarIdentifier],
                Self.calendarAlertRuleApplies(rule, to: event)
            else {
                continue
            }

            let recurringSeriesKey = Self.calendarAlertRecurringSeriesKey(for: event)
            if recurringSeriesKey != nil, !includesRecurringSeries {
                continue
            }
            let eventKey = Self.calendarAlertEventKey(for: event)
            guard processedEventKeys.insert(eventKey).inserted else { continue }

            let configuredAlerts = rule.alerts(isAllDay: event.isAllDay)
            let desiredAlarms = configuredAlerts.compactMap {
                calendarAlarm(from: $0, for: event)
            }

            if !configuredAlerts.isEmpty,
               desiredAlarms.isEmpty,
               configuredAlerts.allSatisfy({ $0.timingKind == .timeToLeave }) {
                continue
            }
            let existingAlarms = event.alarms ?? []
            let resolvedAlarms = Self.resolvedCalendarAlarms(
                existing: existingAlarms,
                desired: desiredAlarms,
                overwriteExisting: rule.overwriteExistingAlerts,
                maximumAlarmCount: Self.maximumCalendarAlarmCount(for: event.calendar)
            )
            guard !Self.calendarAlarmsAreEquivalent(existingAlarms, resolvedAlarms) else {
                continue
            }

            event.alarms = resolvedAlarms.isEmpty ? nil : resolvedAlarms

            do {
                try eventStore.save(
                    event,
                    span: Self.calendarAlertMutationSpan(for: event),
                    commit: false
                )
                result.updatedCount += 1
            } catch {
                result.failureCount += 1
                CalendarMonitorLog.alerts.error(
                    "Could not apply alert rule to event in calendar \(event.calendar.title, privacy: .private): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        guard result.updatedCount > 0 else { return result }
        do {
            try eventStore.commit()
        } catch {
            result.commitFailed = true
            eventStore.reset()
            CalendarMonitorLog.alerts.error(
                "Could not commit calendar alert rules: \(error.localizedDescription, privacy: .public)"
            )
        }
        return result
    }

    func publishCalendarAlertRuleResult(_ result: CalendarAlertRuleApplicationResult) {
        if result.commitFailed {
            calendarAlertRuleStatusDescription = "Could not commit calendar alert changes."
        } else if result.failureCount > 0 {
            calendarAlertRuleStatusDescription =
                "Updated \(result.updatedCount) event(s); \(result.failureCount) could not be changed."
        } else if result.updatedCount > 0 {
            calendarAlertRuleStatusDescription = "Updated alerts on \(result.updatedCount) event(s)."
            CalendarMonitorLog.alerts.info(
                "Applied calendar alert rules to \(result.updatedCount, privacy: .public) event(s)"
            )
        }
    }

    nonisolated static func calendarAlertRuleSyncEndDate(
        now: Date,
        rules: [CalendarAlertRule],
        lookAheadHours: Int
    ) -> Date {
        let maximumLeadTime = rules.map(\.maximumLeadTime).max() ?? 0
        let configuredWindow = TimeInterval(max(1, lookAheadHours)) * 60 * 60
        let desiredHorizon = max(
            configuredWindow,
            maximumLeadTime + calendarAlertRuleSyncBuffer
        )
        return now.addingTimeInterval(min(maximumCalendarAlertRuleSyncHorizon, desiredHorizon))
    }

    nonisolated static func calendarAlertRuleApplies(
        _ rule: CalendarAlertRule,
        to event: EKEvent
    ) -> Bool {
        guard event.status != .canceled else { return false }

        if let currentUser = event.attendees?.first(where: \.isCurrentUser),
           currentUser.participantStatus == .declined {
            return false
        }

        switch rule.scope {
        case .allEvents:
            return true
        case .invitationsOnly:
            if let organizer = event.organizer {
                return !organizer.isCurrentUser
            }
            return event.attendees?.contains(where: \.isCurrentUser) == true
        }
    }

    nonisolated static func calendarAlertRecurringSeriesKey(for event: EKEvent) -> String? {
        guard event.hasRecurrenceRules, !event.isDetached else { return nil }
        let identity = AlertCalendarString.trimmedNonEmpty(event.calendarItemExternalIdentifier)
            ?? AlertCalendarString.trimmedNonEmpty(event.eventIdentifier)
        guard let identity else { return nil }
        return "\(event.calendar.calendarIdentifier)|\(identity)"
    }

    nonisolated static func calendarAlertEventKey(for event: EKEvent) -> String {
        let identity = AlertCalendarString.trimmedNonEmpty(event.eventIdentifier)
            ?? AlertCalendarString.trimmedNonEmpty(event.calendarItemExternalIdentifier)
            ?? AlertCalendarString.trimmedNonEmpty(event.title)
            ?? "untitled"
        return [
            event.calendar.calendarIdentifier,
            identity,
            String(Int(event.startDate.timeIntervalSinceReferenceDate.rounded())),
        ].joined(separator: "|")
    }

    nonisolated static func calendarAlertMutationSpan(for event: EKEvent) -> EKSpan {
        // Saving a recurring invitation with `.futureEvents` can split the provider-backed
        // series and surface both the original and the split as separate events.
        // Per-occurrence alarm overrides match Calendar's safe behavior without duplicating it.
        .thisEvent
    }

    func calendarAlarm(from alert: CalendarEventAlert, for event: EKEvent) -> EKAlarm? {
        let normalized = alert.normalized
        let offset: TimeInterval

        switch normalized.timingKind {
        case .relative:
            offset = TimeInterval(normalized.relativeOffsetSeconds)
        case .timeToLeave:
            let travelTime = EventTravelTimeResolver.travelTime(for: event)
            guard travelTime >= 60 else { return nil }
            offset = -travelTime
        }

        return EKAlarm(relativeOffset: offset)
    }

    nonisolated static func resolvedCalendarAlarms(
        existing: [EKAlarm],
        desired: [EKAlarm],
        overwriteExisting: Bool,
        maximumAlarmCount: Int? = nil
    ) -> [EKAlarm] {
        let resolved: [EKAlarm]
        if overwriteExisting {
            resolved = desired
        } else {
            var merged = existing
            var signatures = Set(existing.map(calendarAlarmSignature))
            for alarm in desired {
                if signatures.insert(calendarAlarmSignature(alarm)).inserted {
                    merged.append(alarm)
                }
            }
            resolved = merged
        }

        guard let maximumAlarmCount else { return resolved }
        return Array(resolved.prefix(max(0, maximumAlarmCount)))
    }

    nonisolated static func maximumCalendarAlarmCount(for calendar: EKCalendar) -> Int? {
        calendar.source.sourceType == .exchange ? 1 : nil
    }

    nonisolated static func calendarAlarmsAreEquivalent(
        _ lhs: [EKAlarm],
        _ rhs: [EKAlarm]
    ) -> Bool {
        lhs.map(calendarAlarmSignature).sorted() == rhs.map(calendarAlarmSignature).sorted()
    }

    nonisolated static func calendarAlarmSignature(_ alarm: EKAlarm) -> String {
        let trigger: String
        if let absoluteDate = alarm.absoluteDate {
            trigger = "absolute:\(Int(absoluteDate.timeIntervalSinceReferenceDate.rounded()))"
        } else {
            trigger = "relative:\(Int(alarm.relativeOffset.rounded()))"
        }

        return [
            trigger,
            "type:\(alarm.type.rawValue)",
            "sound:\(alarm.soundName?.lowercased() ?? "")",
            "email:\(alarm.emailAddress?.lowercased() ?? "")",
            "proximity:\(alarm.proximity.rawValue)",
            "location:\(alarm.structuredLocation?.title?.lowercased() ?? "")",
        ].joined(separator: "|")
    }
}
