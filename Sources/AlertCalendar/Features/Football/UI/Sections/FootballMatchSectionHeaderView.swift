import SwiftUI

struct FootballMatchSectionHeaderView: View {
    let match: FootballFixtureMatch
    let display: FootballMenuBarDisplay?
    let showsScore: Bool
    let showsTeamNames: Bool
    let showsTeamLogos: Bool
    var availableWidth: CGFloat? = nil

    var accessories: FootballStatusAccessoriesData {
        FootballStatusAccessoriesData.resolved(for: match)
    }

    var body: some View {
        if let availableWidth {
            constrainedHeader(width: availableWidth)
        } else {
            flexibleHeader
        }
    }

    private var flexibleHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            FootballMatchSectionTeamHeaderView(
                team: match.homeTeam,
                localLogoPath: display?.homeLocalLogoPath,
                showsName: showsTeamNames,
                showsLogo: showsTeamLogos
            )
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)

            if showsScore {
                scoreColumn
                    .frame(minWidth: 74, maxWidth: 126, alignment: .center)
                    .layoutPriority(1)
            }

            FootballMatchSectionTeamHeaderView(
                team: match.awayTeam,
                localLogoPath: display?.awayLocalLogoPath,
                showsName: showsTeamNames,
                showsLogo: showsTeamLogos
            )
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .clipped()
    }

    private func constrainedHeader(width: CGFloat) -> some View {
        let horizontalPadding: CGFloat = 16
        let spacing: CGFloat = 8
        let scoreWidth = showsScore ? min(126, max(74, width * 0.22)) : 0
        let totalSpacing = showsScore ? spacing * 2 : spacing
        let innerWidth = max(0, width - horizontalPadding - totalSpacing - scoreWidth)
        let teamColumnWidth = max(0, floor(innerWidth / 2))

        return HStack(alignment: .center, spacing: spacing) {
            FootballMatchSectionTeamHeaderView(
                team: match.homeTeam,
                localLogoPath: display?.homeLocalLogoPath,
                showsName: showsTeamNames,
                showsLogo: showsTeamLogos
            )
            .frame(width: teamColumnWidth, alignment: .center)
            .clipped()

            if showsScore {
                scoreColumn
                    .frame(width: scoreWidth, alignment: .center)
                    .layoutPriority(1)
                    .clipped()
            }

            FootballMatchSectionTeamHeaderView(
                team: match.awayTeam,
                localLogoPath: display?.awayLocalLogoPath,
                showsName: showsTeamNames,
                showsLogo: showsTeamLogos
            )
            .frame(width: teamColumnWidth, alignment: .center)
            .clipped()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: width, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .clipped()
    }

    private var scoreColumn: some View {
        VStack(spacing: 4) {
            if let badgeText = accessories.badgeText {
                HStack(spacing: 4) {
                    FootballStatusBadgeView(text: badgeText)

                    if let warningText = accessories.warningText {
                        FootballStatusWarningIconView(helpText: warningText)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
                        .truncationMode(.tail)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .clipped()
    }
}

struct FootballMatchSectionTeamHeaderView: View {
    let team: FootballTeamSummary
    let localLogoPath: String?
    let showsName: Bool
    let showsLogo: Bool

    var teamName: String {
        FootballFixtureFormatter.teamDisplayName(for: team)
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
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
        .clipped()
    }

    var logoView: some View {
        FootballTeamLogoView(
            localPath: localLogoPath,
            remoteURL: FootballFixtureFormatter.isUnknownTeam(team) ? nil : team.logoURL,
            isUnknown: FootballFixtureFormatter.isUnknownTeam(team),
            usesCircularOutline: team.isNational,
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
    var availableWidth: CGFloat? = nil

    var body: some View {
        let placeholderColumnCount = match.totalGoals <= 1 ? 1 : 2
        let placeholderColumnWidth = availableWidth.map { width in
            placeholderColumnCount == 1 ? width : max(0, (width - 8) / 2)
        }

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

            HStack(alignment: .top, spacing: 8) {
                ForEach(0..<placeholderColumnCount, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 18)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .footballConstrainedWidth(placeholderColumnWidth, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.045))
                    )
                    .clipped()
                }
            }
            .footballConstrainedWidth(availableWidth, alignment: .topLeading)
        }
        .footballConstrainedWidth(availableWidth, alignment: .topLeading)
    }
}
