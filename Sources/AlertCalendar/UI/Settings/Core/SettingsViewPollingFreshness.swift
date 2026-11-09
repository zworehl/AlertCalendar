import SwiftUI

extension SettingsView {
    struct PollingFreshness {
        let title: String
        let checkedDate: Date?
        let fetchedDate: Date?
        let isPartial: Bool
        let appliedDate: Date?

        init(title: String, date: Date?) {
            self.title = title
            self.checkedDate = date
            self.fetchedDate = date
            self.isPartial = false
            self.appliedDate = date
        }

        init(title: String, checkedDate: Date?, fetchedDate: Date?, isPartial: Bool = false, appliedDate: Date? = nil) {
            self.title = title
            self.checkedDate = checkedDate
            self.fetchedDate = fetchedDate
            self.isPartial = isPartial
            self.appliedDate = appliedDate
        }
    }

    var activePollingFreshness: PollingFreshness {
        switch selectedTab {
        case .feeds:
            switch selectedFeedsSubsection {
            case .atmosphere:
                if draft.useAutomaticAstronomyLocation {
                    return PollingFreshness(
                        title: L10n.text("Location"),
                        date: lastAstronomyLocationRefreshDate
                    )
                }
                return PollingFreshness(title: L10n.text("Calendar"), date: lastRefreshDate)
            case .holidays:
                let keys = monitor.snapshotSettings().googleHolidayCountryIDs.map { "google-holidays.\($0.lowercased())" }
                return PollingFreshness(
                    title: L10n.text("Holidays"),
                    checkedDate: externalFeedDiagnostics.latestCheckedDate(sourcePrefix: "google-holidays."),
                    fetchedDate: externalFeedDiagnostics.oldestDataDate(sources: keys),
                    isPartial: externalFeedDiagnostics.hasUnresolvedFailure(sources: keys)
                        || dataRefreshIssues.contains { $0.id.hasPrefix("google-holidays.") || $0.id == "holidays.sync" },
                    appliedDate: externalFeedDiagnostics.latestAppliedDate(sourcePrefix: "google-holidays.")
                )
            case .football:
                let prefix = "football.scoreboard."
                let hasScoreboardChecks = externalFeedDiagnostics.sources.keys.contains { $0.hasPrefix(prefix) }
                return PollingFreshness(
                    title: L10n.text("Football"),
                    checkedDate: [externalFeedDiagnostics.latestCheckedDate(sourcePrefix: prefix),
                                  externalFeedDiagnostics.latestCheckedDate(sourcePrefix: "football.summary")].compactMap { $0 }.max(),
                    fetchedDate: hasScoreboardChecks ? externalFeedDiagnostics.oldestDataDate(sourcePrefix: prefix) : lastFootballRefreshDate,
                    isPartial: externalFeedDiagnostics.hasUnresolvedFailure(sourcePrefix: prefix)
                        || externalFeedDiagnostics.hasUnresolvedFailure(sourcePrefix: "football.summary")
                        || dataRefreshIssues.contains { $0.id.hasPrefix("football.") },
                    appliedDate: externalFeedDiagnostics.latestAppliedDate(sourcePrefix: "football.snapshot")
                )
            case .gameSales:
                let keys = ["steam", "xbox", "playStation", "nintendoSitemap"].map { "game-sales.\($0)" }
                return PollingFreshness(
                    title: L10n.text("Game Sales"),
                    checkedDate: externalFeedDiagnostics.latestCheckedDate(sourcePrefix: "game-sales.") ?? lastGameSalesRefreshDate,
                    fetchedDate: externalFeedDiagnostics.oldestDataDate(sources: keys),
                    isPartial: externalFeedDiagnostics.hasUnresolvedFailure(sources: keys)
                        || dataRefreshIssues.contains { $0.id.hasPrefix("game-sales.") },
                    appliedDate: externalFeedDiagnostics.latestAppliedDate(sourcePrefix: "game-sales.")
                )
            }
        case .integrations:
            return PollingFreshness(title: "Slack", date: lastSlackStatusSyncDate)
        case .general, .calendars, .access:
            return PollingFreshness(title: L10n.text("Calendar"), date: lastRefreshDate)
        }
    }

    @ViewBuilder
    var pollingFreshnessLabel: some View {
        let freshness = activePollingFreshness

        TimelineView(.periodic(from: .now, by: 1)) { context in
            Label {
                Text(Self.pollingFreshnessText(freshness, now: context.date, simplified: draft.useSimplifiedCountdown))
            } icon: {
                Image(systemName: freshness.isPartial ? "exclamationmark.triangle" : "clock.arrow.circlepath")
            }
            .help(freshness.appliedDate.map { L10n.text("Last applied: \($0.formatted(date: .abbreviated, time: .shortened))") } ?? "")
            .font(.caption)
            .foregroundStyle(freshness.isPartial ? Color.orange : Color.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    nonisolated static func pollingFreshnessText(_ freshness: PollingFreshness, now: Date, simplified: Bool) -> String {
        let text: String
        if let fetchedDate = freshness.fetchedDate {
            let fetched = pollingFreshnessElapsedText(from: fetchedDate, to: now, simplified: simplified)
            if let checked = freshness.checkedDate, checked.timeIntervalSince(fetchedDate) >= 1 {
                let elapsed = pollingFreshnessElapsedText(from: checked, to: now, simplified: simplified)
                text = L10n.text("\(freshness.title) fetched \(fetched) · checked \(elapsed)")
            } else { text = L10n.text("\(freshness.title) fetched \(fetched)") }
        } else if let checkedDate = freshness.checkedDate {
            let elapsed = pollingFreshnessElapsedText(from: checkedDate, to: now, simplified: simplified)
            text = L10n.text("\(freshness.title) checked \(elapsed)")
        } else { text = L10n.text("\(freshness.title) not checked yet") }
        return freshness.isPartial ? L10n.text("Partial update · \(text)") : text
    }

    nonisolated static func pollingFreshnessElapsedText(
        from date: Date,
        to now: Date,
        simplified: Bool
    ) -> String {
        AlertCalendarRelativeTimeFormatter.elapsedText(
            from: date,
            to: now,
            simplified: simplified
        )
    }
}
