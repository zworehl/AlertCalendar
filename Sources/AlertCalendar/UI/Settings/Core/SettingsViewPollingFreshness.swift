import SwiftUI

extension SettingsView {
    struct PollingFreshness {
        let title: String
        let checkedDate: Date?
        let fetchedDate: Date?

        init(title: String, date: Date?) {
            self.title = title
            self.checkedDate = date
            self.fetchedDate = date
        }

        init(title: String, checkedDate: Date?, fetchedDate: Date?) {
            self.title = title
            self.checkedDate = checkedDate
            self.fetchedDate = fetchedDate
        }
    }

    var activePollingFreshness: PollingFreshness {
        switch selectedTab {
        case .feeds:
            switch selectedFeedsSubsection {
            case .atmosphere:
                if draft.useAutomaticAstronomyLocation {
                    return PollingFreshness(
                        title: "Location",
                        date: lastAstronomyLocationRefreshDate
                    )
                }
                return PollingFreshness(title: "Calendar", date: lastRefreshDate)
            case .holidays:
                return PollingFreshness(
                    title: "Holidays",
                    checkedDate: externalFeedDiagnostics.latestCheckedDate(
                        sourcePrefix: "google-holidays."
                    ),
                    fetchedDate: externalFeedDiagnostics.latestDataDate(
                        sourcePrefix: "google-holidays."
                    ) ?? googleHolidayLastRefreshDate
                )
            case .football:
                let checkedDates = [
                    externalFeedDiagnostics.latestCheckedDate(sourcePrefix: "football.scoreboard."),
                    externalFeedDiagnostics.latestCheckedDate(sourcePrefix: "football.summary"),
                ].compactMap { $0 }
                let fetchedDates = [
                    externalFeedDiagnostics.latestDataDate(sourcePrefix: "football.scoreboard."),
                    externalFeedDiagnostics.latestDataDate(sourcePrefix: "football.summary"),
                    lastFootballRefreshDate,
                ].compactMap { $0 }
                return PollingFreshness(
                    title: "Football",
                    checkedDate: checkedDates.max(),
                    fetchedDate: fetchedDates.max()
                )
            case .gameSales:
                return PollingFreshness(
                    title: "Game Sales",
                    checkedDate: externalFeedDiagnostics.latestCheckedDate(
                        sourcePrefix: "game-sales."
                    ) ?? lastGameSalesRefreshDate,
                    fetchedDate: externalFeedDiagnostics.latestDataDate(
                        sourcePrefix: "game-sales."
                    )
                )
            }
        case .integrations:
            return PollingFreshness(title: "Slack", date: lastSlackStatusSyncDate)
        case .general, .calendars, .access:
            return PollingFreshness(title: "Calendar", date: lastRefreshDate)
        }
    }

    @ViewBuilder
    var pollingFreshnessLabel: some View {
        let freshness = activePollingFreshness

        TimelineView(.periodic(from: .now, by: 1)) { context in
            Label {
                if let fetchedDate = freshness.fetchedDate {
                    let fetchedElapsedText = Self.pollingFreshnessElapsedText(
                        from: fetchedDate,
                        to: context.date,
                        simplified: draft.useSimplifiedCountdown
                    )
                    if let checkedDate = freshness.checkedDate,
                       checkedDate.timeIntervalSince(fetchedDate) >= 1 {
                        let checkedElapsedText = Self.pollingFreshnessElapsedText(
                            from: checkedDate,
                            to: context.date,
                            simplified: draft.useSimplifiedCountdown
                        )
                        Text("\(freshness.title) fetched \(fetchedElapsedText) · checked \(checkedElapsedText)")
                    } else {
                        Text("\(freshness.title) fetched \(fetchedElapsedText)")
                    }
                } else if let checkedDate = freshness.checkedDate {
                    let elapsedText = Self.pollingFreshnessElapsedText(
                        from: checkedDate,
                        to: context.date,
                        simplified: draft.useSimplifiedCountdown
                    )
                    Text("\(freshness.title) checked \(elapsedText)")
                } else {
                    Text("\(freshness.title) not checked yet")
                }
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
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
