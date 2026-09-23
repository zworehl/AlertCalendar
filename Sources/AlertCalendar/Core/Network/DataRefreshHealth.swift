import Foundation

struct DataRefreshIssue: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let firstFailedAt: Date
    let lastFailedAt: Date
}

/// Tracks unresolved failures separately from lifetime request counters and cached data.
actor DataRefreshHealth {
    static let shared = DataRefreshHealth()
    private var issues: [String: DataRefreshIssue] = [:]

    func restore(_ issue: DataRefreshIssue) {
        guard issues[issue.id].map({ $0.lastFailedAt <= issue.lastFailedAt }) ?? true else { return }
        issues[issue.id] = DataRefreshIssue(
            id: issue.id, title: issue.title, detail: issue.detail,
            firstFailedAt: min(issues[issue.id]?.firstFailedAt ?? issue.firstFailedAt, issue.firstFailedAt),
            lastFailedAt: issue.lastFailedAt
        )
    }

    func observe(source: String, title: String, error: String?, at date: Date) {
        guard issues[source]?.detail != error else { return }
        record(source: source, title: title, error: error, at: date)
    }

    func record(source: String, title: String, error: String?, at date: Date = Date()) {
        guard let error else {
            issues[source] = nil
            return
        }
        issues[source] = DataRefreshIssue(
            id: source, title: title, detail: error,
            firstFailedAt: issues[source]?.firstFailedAt ?? date,
            lastFailedAt: date
        )
    }

    func removeSources(withPrefix prefix: String, except retained: Set<String> = []) {
        issues = issues.filter { !$0.key.hasPrefix(prefix) || retained.contains($0.key) }
    }

    func snapshot() -> [DataRefreshIssue] {
        issues.values.sorted { $0.title == $1.title ? $0.id < $1.id : $0.title < $1.title }
    }
}

struct DataRefreshNotificationPolicy {
    static let gracePeriod: TimeInterval = 5 * 60
    static let reminderInterval: TimeInterval = 60 * 60
    var lastNotificationDate: Date?

    func notificationBody(issues: [DataRefreshIssue], now: Date) -> String? {
        guard lastNotificationDate.map({ now.timeIntervalSince($0) >= Self.reminderInterval }) ?? true else {
            return nil
        }
        let titles = Set(issues.filter {
            now.timeIntervalSince($0.firstFailedAt) >= Self.gracePeriod
        }.map(\.title)).sorted()
        guard !titles.isEmpty else { return nil }
        let names = titles.prefix(3).joined(separator: ", ")
        let extra = titles.count > 3 ? " and \(titles.count - 3) more" : ""
        return "Could not update \(names)\(extra). Some information may be out of date. Open Settings → Access → Diagnostics for details and use Refresh Now to retry."
    }
}
