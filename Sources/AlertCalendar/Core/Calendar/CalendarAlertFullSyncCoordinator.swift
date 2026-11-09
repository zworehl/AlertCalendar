import Foundation

struct CalendarAlertRuleApplicationResult: Equatable, Sendable {
    var updatedCount = 0
    var failureCount = 0
    var commitFailed = false

    var succeeded: Bool { failureCount == 0 && !commitFailed }

    mutating func merge(_ other: Self) {
        updatedCount += other.updatedCount
        failureCount += other.failureCount
        commitFailed = commitFailed || other.commitFailed
    }
}

struct CalendarAlertFullSyncCheckpoint: Codable, Equatable, Sendable {
    let fingerprint: String
    let windowCount: Int
    var completedWindows: Set<Int> = []
    var retryAttempt = 0
    var nextRetryAt: Date?

    var isComplete: Bool { completedWindows.count == windowCount }
    var pendingWindows: [Int] { (0..<windowCount).filter { !completedWindows.contains($0) } }

    mutating func scheduleRetry(now: Date) {
        retryAttempt = min(6, retryAttempt) + 1
        let delay = min(3_600, 60 * pow(2, Double(min(6, retryAttempt - 1))))
        nextRetryAt = now.addingTimeInterval(delay)
    }
}

struct CalendarAlertFullSyncOutcome: Sendable {
    var changes = CalendarAlertRuleApplicationResult()
    var completedWindowCount = 0
    var isComplete = false
    var isCancelled = false
    var nextRetryAt: Date?
}

/// Checkpoints committed windows separately from the final successful fingerprint.
/// Failures retry only missing windows; cancellation and relaunch retain progress.
@MainActor
final class CalendarAlertFullSyncCoordinator {
    // v2 invalidates older completion markers which could include failed events.
    nonisolated static let completedFingerprintKey = "calendarAlertRuleFullSyncFingerprint.v2"
    nonisolated static let checkpointKey = "calendarAlertRuleFullSyncCheckpoint.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    func isComplete(fingerprint: String) -> Bool {
        defaults.string(forKey: Self.completedFingerprintKey) == fingerprint
    }

    func checkpoint(fingerprint: String, windowCount: Int) -> CalendarAlertFullSyncCheckpoint {
        if let data = defaults.data(forKey: Self.checkpointKey),
           let value = try? JSONDecoder().decode(CalendarAlertFullSyncCheckpoint.self, from: data),
           value.fingerprint == fingerprint, value.windowCount == windowCount,
           value.retryAttempt >= 0,
           value.completedWindows.allSatisfy({ (0..<windowCount).contains($0) }) {
            return value
        }
        return CalendarAlertFullSyncCheckpoint(fingerprint: fingerprint, windowCount: windowCount)
    }

    func isRetryDue(fingerprint: String, windowCount: Int, now: Date) -> Bool {
        guard !isComplete(fingerprint: fingerprint) else { return false }
        let value = checkpoint(fingerprint: fingerprint, windowCount: windowCount)
        return value.nextRetryAt.map { now >= $0 } ?? true
    }

    func hasPendingRetry(now: Date) -> Bool {
        guard let data = defaults.data(forKey: Self.checkpointKey),
              let value = try? JSONDecoder().decode(CalendarAlertFullSyncCheckpoint.self, from: data),
              !value.isComplete, let nextRetryAt = value.nextRetryAt else { return false }
        return now >= nextRetryAt
    }

    func deferPendingRetry(now: Date) {
        guard let data = defaults.data(forKey: Self.checkpointKey),
              var value = try? JSONDecoder().decode(CalendarAlertFullSyncCheckpoint.self, from: data),
              !value.isComplete else { return }
        value.scheduleRetry(now: now)
        save(value)
    }

    func clearProgress(includeCompletion: Bool) {
        defaults.removeObject(forKey: Self.checkpointKey)
        if includeCompletion { defaults.removeObject(forKey: Self.completedFingerprintKey) }
    }

    func run(
        fingerprint: String,
        windowCount: Int,
        force: Bool = false,
        now: () -> Date,
        applyWindow: (Int) -> CalendarAlertRuleApplicationResult,
        progress: (Int, Int) -> Void = { _, _ in }
    ) async -> CalendarAlertFullSyncOutcome {
        var outcome = CalendarAlertFullSyncOutcome()
        guard !Task.isCancelled else { outcome.isCancelled = true; return outcome }
        if !force, isComplete(fingerprint: fingerprint) {
            outcome.completedWindowCount = windowCount
            outcome.isComplete = true
            return outcome
        }
        var value = force
            ? CalendarAlertFullSyncCheckpoint(fingerprint: fingerprint, windowCount: windowCount)
            : checkpoint(fingerprint: fingerprint, windowCount: windowCount)
        if !force, let retryAt = value.nextRetryAt, now() < retryAt {
            outcome.completedWindowCount = value.completedWindows.count
            outcome.nextRetryAt = retryAt
            return outcome
        }
        // A partial new configuration can replace old alarms. Reverting that
        // configuration must scan again, not trust the previous success marker.
        defaults.removeObject(forKey: Self.completedFingerprintKey)
        save(value)
        for index in value.pendingWindows {
            guard !Task.isCancelled else { outcome.isCancelled = true; break }
            let result = applyWindow(index)
            outcome.changes.merge(result)
            if result.succeeded { value.completedWindows.insert(index) }
            save(value)
            progress(value.completedWindows.count, windowCount)
            if result.commitFailed { break }
            await Task.yield()
        }
        outcome.isCancelled = outcome.isCancelled || Task.isCancelled
        outcome.completedWindowCount = value.completedWindows.count
        outcome.isComplete = value.isComplete && !outcome.isCancelled
        if outcome.isComplete {
            defaults.set(fingerprint, forKey: Self.completedFingerprintKey)
            defaults.removeObject(forKey: Self.checkpointKey)
        } else if !outcome.isCancelled {
            value.scheduleRetry(now: now())
            outcome.nextRetryAt = value.nextRetryAt
            save(value)
        }
        return outcome
    }

    private func save(_ checkpoint: CalendarAlertFullSyncCheckpoint) {
        if let data = try? JSONEncoder().encode(checkpoint) {
            defaults.set(data, forKey: Self.checkpointKey)
        }
    }
}
