import CryptoKit
import EventKit
import Foundation

struct CalendarAlertRuleScanWindow: Equatable {
    let start: Date
    let end: Date
}

extension CalendarMonitor {
    nonisolated static let calendarAlertRuleFullSyncFingerprintKey =
        "calendarAlertRuleFullSyncFingerprint.v1"

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
        let storedFingerprint = defaults.string(
            forKey: Self.calendarAlertRuleFullSyncFingerprintKey
        )

        if calendarAlertFullSyncFingerprintInProgress == fingerprint,
           calendarAlertFullSyncTask != nil {
            return
        }
        guard force || storedFingerprint != fingerprint else { return }

        calendarAlertFullSyncTask?.cancel()
        let token = UUID()
        calendarAlertFullSyncToken = token
        calendarAlertFullSyncFingerprintInProgress = fingerprint
        calendarAlertRuleStatusDescription = "Starting complete calendar alert sync…"

        calendarAlertFullSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performCompleteCalendarAlertRuleSync(
                token: token,
                fingerprint: fingerprint,
                rulesByCalendarID: rulesByCalendarID,
                calendars: calendars
            )
        }
    }

    func performCompleteCalendarAlertRuleSync(
        token: UUID,
        fingerprint: String,
        rulesByCalendarID: [String: CalendarAlertRule],
        calendars: [EKCalendar]
    ) async {
        defer {
            if calendarAlertFullSyncToken == token {
                calendarAlertFullSyncTask = nil
                calendarAlertFullSyncToken = nil
                calendarAlertFullSyncFingerprintInProgress = nil
            }
        }

        let windows = Self.completeCalendarAlertRuleScanWindows()
        CalendarMonitorLog.alerts.info(
            "Starting complete calendar alert sync across \(windows.count, privacy: .public) date windows"
        )
        var processedEventKeys: Set<String> = []
        var totalResult = CalendarAlertRuleApplicationResult()
        var completedAllWindows = true

        for (index, window) in windows.enumerated() {
            guard !Task.isCancelled else { return }
            let result = applyCalendarAlertRules(
                in: window,
                rulesByCalendarID: rulesByCalendarID,
                calendars: calendars,
                processedEventKeys: &processedEventKeys,
                includesRecurringSeries: false
            )
            totalResult.merge(result)

            if result.commitFailed {
                completedAllWindows = false
                break
            }

            let completedWindowCount = index + 1
            if completedWindowCount == windows.count || completedWindowCount.isMultiple(of: 10) {
                let percentage = Int(
                    (Double(completedWindowCount) / Double(max(1, windows.count))) * 100
                )
                calendarAlertRuleStatusDescription =
                    "Complete calendar alert sync: \(percentage)%"
            }
            await Task.yield()
        }

        guard !Task.isCancelled else { return }
        if completedAllWindows {
            defaults.set(fingerprint, forKey: Self.calendarAlertRuleFullSyncFingerprintKey)
        }

        if totalResult.commitFailed {
            calendarAlertRuleStatusDescription = "Complete calendar alert sync could not finish."
        } else if totalResult.failureCount > 0 {
            calendarAlertRuleStatusDescription =
                "Complete sync updated \(totalResult.updatedCount) event(s); \(totalResult.failureCount) could not be changed."
        } else {
            calendarAlertRuleStatusDescription =
                "Complete sync finished: \(totalResult.updatedCount) event(s) updated."
        }
        CalendarMonitorLog.alerts.info(
            "Complete calendar alert sync finished: \(totalResult.updatedCount, privacy: .public) updated, \(totalResult.failureCount, privacy: .public) failed"
        )
    }

    func cancelCompleteCalendarAlertRuleSync(clearStoredFingerprint: Bool) {
        calendarAlertFullSyncTask?.cancel()
        calendarAlertFullSyncTask = nil
        calendarAlertFullSyncToken = nil
        calendarAlertFullSyncFingerprintInProgress = nil
        if clearStoredFingerprint,
           defaults.object(forKey: Self.calendarAlertRuleFullSyncFingerprintKey) != nil {
            defaults.removeObject(forKey: Self.calendarAlertRuleFullSyncFingerprintKey)
        }
    }
}
