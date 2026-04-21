import AppKit
import CoreLocation
import MapKit
import SwiftUI

struct FootballMatchStatsSection: View {
    @EnvironmentObject private var monitor: CalendarMonitor
    let match: FootballFixtureMatch
    let display: FootballMenuBarDisplay?
    let showsScoreHeader: Bool

    @State private var statistics: [FootballMatchStatistic] = []
    @State private var isLoading = false
    @State private var hasAttemptedLoad = false
    @State private var loadTask: Task<Void, Never>?

    private var requestKey: String {
        let statusPeriod = match.statusPeriod.map(String.init) ?? "n/a"
        return "\(match.id)|\(match.homeScore)|\(match.awayScore)|\(match.statusText)|\(statusPeriod)"
    }

    var body: some View {
        Group {
            if match.statusState == .scheduled {
                EmptyView()
            } else if statistics.isEmpty && (!hasAttemptedLoad || isLoading) {
                FootballMatchStatsLoadingView(
                    match: match,
                    display: display,
                    showsScore: showsScoreHeader
                )
            } else if !statistics.isEmpty {
                FootballMatchStatsView(
                    match: match,
                    display: display,
                    stats: statistics,
                    showsScore: showsScoreHeader
                )
            }
        }
        .onAppear {
            startLoadingStatistics()
        }
        .onChange(of: requestKey) { _ in
            startLoadingStatistics()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func startLoadingStatistics() {
        loadTask?.cancel()

        guard match.statusState != .scheduled else {
            statistics = []
            isLoading = false
            hasAttemptedLoad = true
            return
        }

        let currentRequestKey = requestKey
        let footballClient = monitor.footballClient
        let hadStatistics = !statistics.isEmpty
        isLoading = true
        if !hadStatistics {
            hasAttemptedLoad = false
        }

        loadTask = Task {
            do {
                let fetchedStatistics = try await footballClient.fetchMatchStatistics(for: match)
                await MainActor.run {
                    guard currentRequestKey == requestKey else { return }
                    statistics = fetchedStatistics
                    isLoading = false
                    hasAttemptedLoad = true
                }
            } catch {
                await MainActor.run {
                    guard currentRequestKey == requestKey else { return }
                    isLoading = false
                    hasAttemptedLoad = true
                }
            }
        }
    }
}

struct FootballMatchStatsView: View {
    let match: FootballFixtureMatch
    let display: FootballMenuBarDisplay?
    let stats: [FootballMatchStatistic]
    let showsScore: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FootballMatchSectionHeaderView(
                match: match,
                display: display,
                showsScore: showsScore,
                showsTeamNames: true,
                showsTeamLogos: true
            )

            VStack(spacing: 6) {
                ForEach(stats) { stat in
                    HStack(spacing: 8) {
                        Text(stat.homeValue)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text(stat.label.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text(stat.awayValue)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.045))
                    )
                }
            }
        }
    }
}

struct FootballMatchStatsLoadingView: View {
    let match: FootballFixtureMatch
    let display: FootballMenuBarDisplay?
    let showsScore: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FootballMatchSectionHeaderView(
                match: match,
                display: display,
                showsScore: showsScore,
                showsTeamNames: true,
                showsTeamLogos: true
            )

            VStack(spacing: 6) {
                ForEach(0..<10, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 22)
                }
            }
        }
    }
}
