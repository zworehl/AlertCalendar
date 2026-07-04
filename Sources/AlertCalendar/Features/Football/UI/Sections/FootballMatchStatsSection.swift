import SwiftUI

struct FootballMatchStatsSection: View {
    @EnvironmentObject private var monitor: CalendarMonitor
    let match: FootballFixtureMatch
    let display: FootballMenuBarDisplay?
    let showsScoreHeader: Bool
    let outcomeProbabilities: FootballMatchOutcomeProbabilities?
    var availableWidth: CGFloat? = nil

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
                    showsScore: showsScoreHeader,
                    outcomeProbabilities: outcomeProbabilities,
                    availableWidth: availableWidth
                )
            } else if !statistics.isEmpty {
                FootballMatchStatsView(
                    match: match,
                    display: display,
                    stats: statistics,
                    showsScore: showsScoreHeader,
                    outcomeProbabilities: outcomeProbabilities,
                    availableWidth: availableWidth
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
    let outcomeProbabilities: FootballMatchOutcomeProbabilities?
    var availableWidth: CGFloat? = nil
    private let valueColumnWidth: CGFloat = 64
    private let statRowHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FootballMatchSectionHeaderView(
                match: match,
                display: display,
                showsScore: showsScore,
                showsTeamNames: true,
                showsTeamLogos: true,
                availableWidth: availableWidth
            )

            if let outcomeProbabilities {
                FootballOutcomeProbabilityBar(
                    match: match,
                    display: display,
                    probabilities: outcomeProbabilities,
                    style: .contextual,
                    availableWidth: availableWidth
                )
            }

            VStack(spacing: 6) {
                ForEach(stats) { stat in
                    statisticRow(stat)
                }
            }
            .footballConstrainedWidth(availableWidth)
        }
        .footballConstrainedWidth(availableWidth)
    }

    private func statisticRow(_ stat: FootballMatchStatistic) -> some View {
        GeometryReader { proxy in
            let rowWidth = max(0, proxy.size.width)
            let horizontalPadding: CGFloat = 16
            let spacing: CGFloat = 12
            let availableContentWidth = max(0, rowWidth - horizontalPadding - spacing)
            let constrainedValueWidth = min(
                valueColumnWidth,
                max(34, floor(availableContentWidth * 0.22))
            )
            let labelWidth = max(34, availableContentWidth - (constrainedValueWidth * 2))

            HStack(spacing: 6) {
                Text(stat.homeValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: constrainedValueWidth, alignment: .center)
                    .clipped()

                Text(stat.label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .truncationMode(.tail)
                    .frame(width: labelWidth, alignment: .center)
                    .clipped()

                Text(stat.awayValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: constrainedValueWidth, alignment: .center)
                    .clipped()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: rowWidth, height: statRowHeight, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
            .clipped()
        }
        .frame(height: statRowHeight)
        .footballConstrainedWidth(availableWidth)
    }
}

struct FootballMatchStatsLoadingView: View {
    let match: FootballFixtureMatch
    let display: FootballMenuBarDisplay?
    let showsScore: Bool
    let outcomeProbabilities: FootballMatchOutcomeProbabilities?
    var availableWidth: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FootballMatchSectionHeaderView(
                match: match,
                display: display,
                showsScore: showsScore,
                showsTeamNames: true,
                showsTeamLogos: true,
                availableWidth: availableWidth
            )

            if let outcomeProbabilities {
                FootballOutcomeProbabilityBar(
                    match: match,
                    display: display,
                    probabilities: outcomeProbabilities,
                    style: .contextual,
                    availableWidth: availableWidth
                )
            }

            VStack(spacing: 6) {
                ForEach(0..<10, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 22)
                }
            }
            .footballConstrainedWidth(availableWidth)
        }
        .footballConstrainedWidth(availableWidth)
    }
}
