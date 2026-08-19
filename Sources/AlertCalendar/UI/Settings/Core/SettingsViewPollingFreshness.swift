import SwiftUI

extension SettingsView {
    struct PollingFreshness {
        let title: String
        let date: Date?
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
                    date: googleHolidayLastRefreshDate
                )
            case .football:
                return PollingFreshness(
                    title: "Football",
                    date: lastFootballRefreshDate
                )
            case .gameSales:
                return PollingFreshness(
                    title: "Game Sales",
                    date: lastGameSalesRefreshDate
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
                if let date = freshness.date {
                    let elapsedText = Self.pollingFreshnessElapsedText(
                        from: date,
                        to: context.date,
                        simplified: draft.useSimplifiedCountdown
                    )
                    Text("\(freshness.title) updated \(elapsedText)")
                } else {
                    Text("\(freshness.title) not updated yet")
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
