import CryptoKit
import EventKit
import Foundation

struct CalendarAlertRuleScanWindow: Equatable {
    let start: Date
    let end: Date
}

extension CalendarMonitor {
    nonisolated static let calendarAlertRuleFullSyncFingerprintKey =
        CalendarAlertFullSyncCoordinator.completedFingerprintKey

    nonisolated static func completeCalendarAlertRuleScanWindows(
        start: Date = .distantPast,
        end: Date = .distantFuture
    ) -> [CalendarAlertRuleScanWindow] {
        guard start < end else { return [] }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        var windows: [CalendarAlertRuleScanWindow] = []
        var cursor = start

        while cursor < end {
            let proposedEnd = calendar.date(byAdding: .year, value: 4, to: cursor) ?? end
            let windowEnd = min(proposedEnd, end)
            guard windowEnd > cursor else { break }
            windows.append(CalendarAlertRuleScanWindow(start: cursor, end: windowEnd))
            cursor = windowEnd
        }

        return windows
    }

    nonisolated static func calendarAlertRuleFingerprint(
        _ rules: [CalendarAlertRule]
    ) -> String? {
        let sortedRules = rules.sorted { $0.calendarID < $1.calendarID }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(sortedRules) else { return nil }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func scheduleCompleteCalendarAlertRuleSync(
        enabledRules: [CalendarAlertRule],
        rulesByCalendarID: [String: CalendarAlertRule],
        calendars: [EKCalendar],
        force: Bool
    ) {
        guard let fingerprint = Self.calendarAlertRuleFingerprint(enabledRules) else { return }
        let coordinator = CalendarAlertFullSyncCoordinator(defaults: defaults)
        if calendarAlertFullSyncFingerprintInProgress == fingerprint, calendarAlertFullSyncTask != nil { return }
        guard force || !coordinator.isComplete(fingerprint: fingerprint) else { return }
        let windowCount = Self.completeCalendarAlertRuleScanWindows().count
        guard force || coordinator.isRetryDue(fingerprint: fingerprint, windowCount: windowCount, now: fixedSecondNow()) else { return }

        calendarAlertFullSyncTask?.cancel()
        let token = UUID()
        calendarAlertFullSyncToken = token
        calendarAlertFullSyncFingerprintInProgress = fingerprint
        calendarAlertRuleStatusDescription = "Starting complete calendar alert sync…"
        calendarAlertFullSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performCompleteCalendarAlertRuleSync(
                token: token, fingerprint: fingerprint, rulesByCalendarID: rulesByCalendarID,
                calendars: calendars, force: force
            )
        }
    }

    func performCompleteCalendarAlertRuleSync(
        token: UUID,
        fingerprint: String,
        rulesByCalendarID: [String: CalendarAlertRule],
        calendars: [EKCalendar],
        force: Bool = false
    ) async {
        defer {
            if calendarAlertFullSyncToken == token {
                calendarAlertFullSyncTask = nil
                calendarAlertFullSyncToken = nil
                calendarAlertFullSyncFingerprintInProgress = nil
            }
        }
        guard !Task.isCancelled, calendarAlertFullSyncToken == token else { return }
        let windows = Self.completeCalendarAlertRuleScanWindows()
        let coordinator = CalendarAlertFullSyncCoordinator(defaults: defaults)
        var processedEventKeys: Set<String> = []
        let outcome = await coordinator.run(
            fingerprint: fingerprint, windowCount: windows.count, force: force,
            now: { self.fixedSecondNow() },
            applyWindow: { index in
                self.applyCalendarAlertRules(
                    in: windows[index], rulesByCalendarID: rulesByCalendarID,
                    calendars: calendars, processedEventKeys: &processedEventKeys,
                    includesRecurringSeries: false
                )
            },
            progress: { completed, total in
                let percentage = Int(Double(completed) / Double(max(1, total)) * 100)
                let status = "Complete calendar alert sync: \(percentage)%"
                if self.calendarAlertRuleStatusDescription != status {
                    self.calendarAlertRuleStatusDescription = status
                }
            }
        )
        guard !outcome.isCancelled, !Task.isCancelled, calendarAlertFullSyncToken == token else { return }
        let result = outcome.changes
        if !outcome.isComplete {
            calendarAlertRuleStatusDescription = result.commitFailed
                ? "Complete calendar alert sync could not finish."
                : "Complete sync updated \(result.updatedCount) event(s); \(result.failureCount) could not be changed."
        } else {
            calendarAlertRuleStatusDescription = "Complete sync finished: \(result.updatedCount) event(s) updated."
        }
        await DataRefreshHealth.shared.record(
            source: "calendar.alert-sync", title: L10n.text("Calendar"),
            error: outcome.isComplete ? nil : L10n.text("Calendar alert changes could not be completed. Failed date ranges will be retried automatically."),
            at: fixedSecondNow()
        )
        CalendarMonitorLog.alerts.info("Complete calendar alert sync pass: \(outcome.completedWindowCount, privacy: .public) windows complete; \(result.failureCount, privacy: .public) failed")
    }

    func retryIncompleteCalendarAlertRuleSyncIfNeeded(now: Date) {
        let coordinator = CalendarAlertFullSyncCoordinator(defaults: defaults)
        guard hasEventsAccess, calendarAlertFullSyncTask == nil, coordinator.hasPendingRetry(now: now) else { return }
        let settings = snapshotSettings()
        let enabledIDs = Set(CalendarAlertRule.normalized(settings.calendarAlertRules).filter {
            $0.isEnabled && settings.selectedEventCalendarIDs.contains($0.calendarID)
        }.map(\.calendarID))
        guard !enabledIDs.isEmpty else {
            cancelCompleteCalendarAlertRuleSync(clearStoredFingerprint: true)
            return
        }
        guard eventStore.calendars(for: .event).contains(where: {
            enabledIDs.contains($0.calendarIdentifier) && $0.allowsContentModifications
        }) else {
            coordinator.deferPendingRetry(now: now)
            return
        }
        applyCalendarAlertRules(now: now, settings: settings, reason: .periodic)
    }

    func cancelCompleteCalendarAlertRuleSync(clearStoredFingerprint: Bool) {
        calendarAlertFullSyncTask?.cancel()
        calendarAlertFullSyncTask = nil
        calendarAlertFullSyncToken = nil
        calendarAlertFullSyncFingerprintInProgress = nil
        if clearStoredFingerprint {
            CalendarAlertFullSyncCoordinator(defaults: defaults).clearProgress(includeCompletion: true)
            Task { await DataRefreshHealth.shared.record(source: "calendar.alert-sync", title: L10n.text("Calendar"), error: nil) }
        }
    }
}
