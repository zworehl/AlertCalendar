import SwiftUI

struct FootballGoalScorersSection: View {
    @EnvironmentObject private var monitor: CalendarMonitor
    let match: FootballFixtureMatch
    let display: FootballMenuBarDisplay?
    let showsTeamHeader: Bool
    let showsScoreHeader: Bool
    var availableWidth: CGFloat? = nil

    @State private var scorers: FootballMatchGoalScorers?
    @State private var isLoading = false
    @State private var hasAttemptedLoad = false
    @State private var loadTask: Task<Void, Never>?
    @State private var retryTask: Task<Void, Never>?
    @State private var retryAttempt = 0
    let incompleteRetryDelayNanoseconds: UInt64 = 12_000_000_000
    let maximumIncompleteRetryCount = 4

    var requestKey: String {
        let statusDetail = match.statusDetailText ?? ""
        let statusPeriod = match.statusPeriod.map(String.init) ?? "n/a"
        return "\(match.id)|\(match.homeScore)|\(match.awayScore)|\(match.statusText)|\(statusDetail)|\(statusPeriod)"
    }

    var resolvedScorerCount: Int {
        Self.scorerCount(for: scorers)
    }

    var shouldRetryIncompleteScorers: Bool {
        match.totalGoals > resolvedScorerCount
    }

    var canRetryIncompleteScorers: Bool {
        shouldRetryIncompleteScorers && retryAttempt < maximumIncompleteRetryCount
    }

    var body: some View {
        Group {
            if match.totalGoals <= 0 {
                EmptyView()
            } else if let scorers,
                      !scorers.home.isEmpty || !scorers.away.isEmpty {
                FootballGoalScorersView(
                    match: match,
                    display: display,
                    scorers: scorers,
                    showsHeader: showsTeamHeader,
                    showsScore: showsScoreHeader,
                    availableWidth: availableWidth
                )
            } else if scorers == nil && (!hasAttemptedLoad || isLoading || canRetryIncompleteScorers) {
                FootballGoalScorersLoadingView(
                    match: match,
                    display: display,
                    showsHeader: showsTeamHeader,
                    showsScore: showsScoreHeader,
                    availableWidth: availableWidth
                )
            }
        }
        .onAppear {
            startLoadingScorers(resetRetryAttempt: true)
        }
        .onChange(of: requestKey) { _ in
            startLoadingScorers(resetRetryAttempt: true)
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
            retryTask?.cancel()
            retryTask = nil
        }
    }

    func startLoadingScorers(resetRetryAttempt: Bool = false) {
        loadTask?.cancel()
        retryTask?.cancel()
        if resetRetryAttempt {
            retryAttempt = 0
        }

        guard match.totalGoals > 0 else {
            scorers = nil
            isLoading = false
            hasAttemptedLoad = true
            return
        }

        let currentRequestKey = requestKey
        let footballClient = monitor.footballClient
        let hadScorers = scorers != nil
        isLoading = true
        if !hadScorers {
            hasAttemptedLoad = false
        }

        loadTask = Task {
            do {
                let fetchedScorers = try await footballClient.fetchGoalScorers(for: match)
                await MainActor.run {
                    guard currentRequestKey == requestKey else { return }
                    scorers = fetchedScorers
                    isLoading = false
                    hasAttemptedLoad = true
                    scheduleRetryIfNeeded(for: currentRequestKey)
                }
            } catch {
                await MainActor.run {
                    guard currentRequestKey == requestKey else { return }
                    isLoading = false
                    hasAttemptedLoad = true
                    scheduleRetryIfNeeded(for: currentRequestKey)
                }
            }
        }
    }

    func scheduleRetryIfNeeded(for currentRequestKey: String) {
        retryTask?.cancel()

        guard canRetryIncompleteScorers else { return }
        let delayMultiplier = UInt64(1 << min(retryAttempt, 3))
        retryAttempt += 1

        retryTask = Task {
            try? await Task.sleep(nanoseconds: incompleteRetryDelayNanoseconds * delayMultiplier)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard currentRequestKey == requestKey else { return }
                startLoadingScorers()
            }
        }
    }

    static func scorerCount(for scorers: FootballMatchGoalScorers?) -> Int {
        (scorers?.home.count ?? 0) + (scorers?.away.count ?? 0)
    }
}

struct FootballGoalScorersView: View {
    let match: FootballFixtureMatch
    let display: FootballMenuBarDisplay?
    let scorers: FootballMatchGoalScorers
    let showsHeader: Bool
    let showsScore: Bool
    var availableWidth: CGFloat? = nil
    let minuteColumnWidth: CGFloat = 34

    var body: some View {
        let homeScorers = sortedScorers(scorers.home)
        let awayScorers = sortedScorers(scorers.away)

        VStack(alignment: .leading, spacing: 6) {
            if showsHeader {
                FootballMatchSectionHeaderView(
                    match: match,
                    display: display,
                    showsScore: showsScore,
                    showsTeamNames: true,
                    showsTeamLogos: true,
                    availableWidth: availableWidth
                )
            }

            scorerColumns(homeScorers: homeScorers, awayScorers: awayScorers)
        }
        .footballConstrainedWidth(availableWidth, alignment: .topLeading)
    }

    @ViewBuilder
    private func scorerColumns(
        homeScorers: [FootballMatchGoalScorer],
        awayScorers: [FootballMatchGoalScorer]
    ) -> some View {
        if Self.usesTwoScorerColumns(
            homeScorerCount: homeScorers.count,
            awayScorerCount: awayScorers.count
        ) {
            let targetRowCount = max(homeScorers.count, awayScorers.count, 1)
            let scorerColumnWidth = availableWidth.map { max(0, ($0 - 8) / 2) }

            HStack(alignment: .top, spacing: 8) {
                scorerColumn(
                    scorers: homeScorers,
                    targetRowCount: targetRowCount,
                    columnWidth: scorerColumnWidth,
                    isEmptySide: homeScorers.isEmpty
                )

                scorerColumn(
                    scorers: awayScorers,
                    targetRowCount: targetRowCount,
                    columnWidth: scorerColumnWidth,
                    isEmptySide: awayScorers.isEmpty
                )
            }
            .footballConstrainedWidth(availableWidth, alignment: .topLeading)
        } else {
            scorerColumn(
                scorers: [],
                targetRowCount: 1,
                columnWidth: availableWidth,
                isEmptySide: true
            )
        }
    }

    static func usesTwoScorerColumns(homeScorerCount: Int, awayScorerCount: Int) -> Bool {
        homeScorerCount + awayScorerCount > 0
    }

    @ViewBuilder
    func scorerColumn(
        scorers: [FootballMatchGoalScorer],
        targetRowCount: Int,
        columnWidth: CGFloat?,
        isEmptySide: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(scorers) { scorer in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(scorer.minute ?? "—")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: minuteColumnWidth, alignment: .center)

                    Text(scorer.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                }
            }

            ForEach(0..<max(0, targetRowCount - scorers.count), id: \.self) { _ in
                scorerPlaceholderRow()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .footballConstrainedWidth(columnWidth, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isEmptySide ? 0 : 0.045))
        )
        .clipped()
    }

    func sortedScorers(_ scorers: [FootballMatchGoalScorer]) -> [FootballMatchGoalScorer] {
        scorers.sorted { lhs, rhs in
            scorerEventIndex(lhs.id) < scorerEventIndex(rhs.id)
        }
    }

    func scorerPlaceholderRow() -> some View {
        HStack(spacing: 4) {
            Text("88'")
                .font(.caption2.weight(.semibold))
                .frame(width: minuteColumnWidth, alignment: .center)
                .hidden()

            Text("Placeholder")
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hidden()
        }
    }

    func scorerEventIndex(_ scorerID: String) -> Int {
        guard let token = scorerID.split(separator: "-").last,
              let index = Int(token) else {
            return .max
        }
        return index
    }
}
