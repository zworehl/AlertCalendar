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

        Label {
            if let date = freshness.date {
                Text("\(freshness.title) updated ")
                    + Text(date, style: .relative)
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
