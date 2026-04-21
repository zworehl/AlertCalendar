import AppKit
import SwiftUI

struct FootballGoalScorersSection: View {
    @EnvironmentObject private var monitor: CalendarMonitor
    let match: FootballFixtureMatch
    let display: FootballMenuBarDisplay?
    let showsTeamHeader: Bool
    let showsScoreHeader: Bool

    @State private var scorers: FootballMatchGoalScorers?
    @State private var isLoading = false
    @State private var hasAttemptedLoad = false
    @State private var loadTask: Task<Void, Never>?
    @State private var retryTask: Task<Void, Never>?
    let incompleteRetryDelayNanoseconds: UInt64 = 12_000_000_000

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
                    showsScore: showsScoreHeader
                )
            } else if scorers == nil && (!hasAttemptedLoad || isLoading || shouldRetryIncompleteScorers) {
                FootballGoalScorersLoadingView(
                    match: match,
                    display: display,
                    showsHeader: showsTeamHeader,
                    showsScore: showsScoreHeader
                )
            }
        }
        .onAppear {
            startLoadingScorers()
        }
        .onChange(of: requestKey) { _ in
            startLoadingScorers()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
            retryTask?.cancel()
            retryTask = nil
        }
    }

    func startLoadingScorers() {
        loadTask?.cancel()
        retryTask?.cancel()

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

        guard shouldRetryIncompleteScorers else { return }

        retryTask = Task {
            try? await Task.sleep(nanoseconds: incompleteRetryDelayNanoseconds)
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
    let minuteColumnWidth: CGFloat = 56

    var body: some View {
        let homeScorers = sortedScorers(scorers.home)
        let awayScorers = sortedScorers(scorers.away)
        let targetRowCount = max(homeScorers.count, awayScorers.count, 1)

        VStack(alignment: .leading, spacing: 6) {
            if showsHeader {
                FootballMatchSectionHeaderView(
                    match: match,
                    display: display,
                    showsScore: showsScore,
                    showsTeamNames: true,
                    showsTeamLogos: true
                )
            }

            HStack(alignment: .top, spacing: 8) {
                scorerColumn(
                    scorers: homeScorers,
                    targetRowCount: targetRowCount
                )

                scorerColumn(
                    scorers: awayScorers,
                    targetRowCount: targetRowCount
                )
            }
        }
    }

    @ViewBuilder
    func scorerColumn(
        scorers: [FootballMatchGoalScorer],
        targetRowCount: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(scorers) { scorer in
                HStack(spacing: 6) {
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
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            ForEach(0..<max(0, targetRowCount - scorers.count), id: \.self) { _ in
                scorerPlaceholderRow()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    func sortedScorers(_ scorers: [FootballMatchGoalScorer]) -> [FootballMatchGoalScorer] {
        scorers.sorted { lhs, rhs in
            scorerEventIndex(lhs.id) < scorerEventIndex(rhs.id)
        }
    }

    func scorerPlaceholderRow() -> some View {
        HStack(spacing: 6) {
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

struct FootballMatchSectionHeaderView: View {
    let match: FootballFixtureMatch
    let display: FootballMenuBarDisplay?
    let showsScore: Bool
    let showsTeamNames: Bool
    let showsTeamLogos: Bool

    var accessories: FootballStatusAccessoriesData {
        FootballStatusAccessoriesData.resolved(for: match)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            FootballMatchSectionTeamHeaderView(
                team: match.homeTeam,
                localLogoPath: display?.homeLocalLogoPath,
                showsName: showsTeamNames,
                showsLogo: showsTeamLogos
            )
            .frame(maxWidth: .infinity, alignment: .center)

            if showsScore {
                HStack {
                    Spacer(minLength: 0)

                    VStack(spacing: 4) {
                        if let badgeText = accessories.badgeText {
                            HStack(spacing: 4) {
                                FootballStatusBadgeView(text: badgeText)

                                if let warningText = accessories.warningText {
                                    FootballStatusWarningIconView(helpText: warningText)
                                }
                            }
                        } else if let warningText = accessories.warningText {
                            FootballStatusWarningIconView(helpText: warningText)
                        }

                        HStack(spacing: 4) {
                            Text(
                                "\(FootballFixtureFormatter.scoreText(match.homeScore)) - \(FootballFixtureFormatter.scoreText(match.awayScore))"
                            )
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.95))

                            if let aggregateText = FootballFixtureFormatter.menuBarAggregateText(for: match) {
                                Text(aggregateText)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        )
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

            FootballMatchSectionTeamHeaderView(
                team: match.awayTeam,
                localLogoPath: display?.awayLocalLogoPath,
                showsName: showsTeamNames,
                showsLogo: showsTeamLogos
            )
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }
}

struct FootballMatchSectionTeamHeaderView: View {
    let team: FootballTeamSummary
    let localLogoPath: String?
    let showsName: Bool
    let showsLogo: Bool

    var teamName: String {
        let trimmedName = team.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty && !FootballFixtureFormatter.isUnknownTeam(team) {
            return trimmedName
        }
        return FootballFixtureFormatter.teamDisplayIdentifier(for: team)
    }

    var body: some View {
        VStack(spacing: 4) {
            if showsLogo {
                logoView
            }

            if showsName {
                Text(teamName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    var logoView: some View {
        FootballTeamLogoView(
            localPath: localLogoPath,
            remoteURL: FootballFixtureFormatter.isUnknownTeam(team) ? nil : team.logoURL,
            isUnknown: FootballFixtureFormatter.isUnknownTeam(team),
            size: 26,
            placeholderSymbolSize: 13
        )
    }
}

struct FootballGoalScorersLoadingView: View {
    let match: FootballFixtureMatch
    let display: FootballMenuBarDisplay?
    let showsHeader: Bool
    let showsScore: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsHeader {
                FootballMatchSectionHeaderView(
                    match: match,
                    display: display,
                    showsScore: showsScore,
                    showsTeamNames: true,
                    showsTeamLogos: true
                )
            }

            HStack(alignment: .top, spacing: 8) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 18)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.045))
                    )
                }
            }
        }
    }
}

struct SplitContextualPanelHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
