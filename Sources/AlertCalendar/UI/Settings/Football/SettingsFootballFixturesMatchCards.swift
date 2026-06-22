import AppKit
import Combine
import SwiftUI

extension SettingsFootballFixturesSectionView {
    @ViewBuilder
    func matchCardTrailingAccessory(_ match: FootballFixtureMatch, isHovered: Bool) -> some View {
        if let badgeText = footballCardTrailingBadgeText(for: match) {
            ZStack(alignment: .trailing) {
                FootballStatusBadgeView(text: badgeText)
                    .opacity(isHovered ? 0 : 1)
                    .scaleEffect(isHovered ? 0.96 : 1)
                    .animation(.easeInOut(duration: 0.14), value: isHovered)

                matchCardActions(match, isVisible: isHovered)
            }
            .fixedSize(horizontal: true, vertical: false)
        } else {
            ZStack(alignment: .trailing) {
                if let trailingText = footballCardTrailingText(for: match) {
                    Text(trailingText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(isHovered ? 0 : 1)
                        .scaleEffect(isHovered ? 0.96 : 1)
                        .animation(.easeInOut(duration: 0.14), value: isHovered)
                }

                matchCardActions(match, isVisible: isHovered)
            }
            .frame(
                minWidth: Self.matchActionButtonSize,
                maxWidth: Self.matchActionSlotWidth,
                alignment: .trailing
            )
        }
    }

    @ViewBuilder
    func matchCardActions(_ match: FootballFixtureMatch, isVisible: Bool) -> some View {
        if managedFootballMatchIDs.contains(match.id) {
            removeMatchButton(match, isVisible: isVisible)
        } else {
            actionIconButton(
                systemName: "plus",
                tint: .green,
                helpText: "Add this event to Apple Calendar",
                isVisible: isVisible
            ) {
                Task {
                    await monitor.addFootballMatchToCalendar(match)
                }
            }
            .disabled(footballTargetCalendarID.isEmpty)
        }
    }

    func removeMatchButton(_ match: FootballFixtureMatch, isVisible: Bool) -> some View {
        actionIconButton(
            systemName: "minus",
            tint: .red,
            helpText: "Remove this event from Apple Calendar",
            isVisible: isVisible
        ) {
            monitor.removeFootballMatchFromCalendar(match)
        }
    }

    func actionIconButton(
        systemName: String,
        tint: Color,
        helpText: String,
        isVisible: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: Self.matchActionButtonSize, height: Self.matchActionButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(tint.opacity(0.28), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.94)
        .allowsHitTesting(isVisible)
        .animation(.easeInOut(duration: 0.14), value: isVisible)
    }

    @ViewBuilder
    func fixtureTitleRow(_ match: FootballFixtureMatch, accessories: FootballStatusAccessoriesData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                teamLabelRow(match.homeTeam, logoLeading: false)

                if match.hasVisibleScore {
                    Text(FootballFixtureFormatter.scoreText(match.homeScore))
                        .frame(minWidth: 10, alignment: .center)
                }

                Text("-")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 8, alignment: .center)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)

                if match.hasVisibleScore {
                    Text(FootballFixtureFormatter.scoreText(match.awayScore))
                        .frame(minWidth: 10, alignment: .center)
                }

                teamLabelRow(match.awayTeam, logoLeading: true)

                if accessories.hasAccessories {
                    FootballStatusAccessoriesView(data: accessories)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    func teamLabelRow(_ team: FootballTeamSummary, logoLeading: Bool) -> some View {
        HStack(spacing: 4) {
            if logoLeading {
                FootballTeamLogoView(
                    localPath: localTeamLogoPath(for: team),
                    remoteURL: team.logoURL,
                    isUnknown: FootballFixtureFormatter.isUnknownTeam(team),
                    usesCircularOutline: team.isNational,
                    size: 18,
                    placeholderSymbolSize: 9
                )
                teamNameText(team)
            } else {
                teamNameText(team)
                FootballTeamLogoView(
                    localPath: localTeamLogoPath(for: team),
                    remoteURL: team.logoURL,
                    isUnknown: FootballFixtureFormatter.isUnknownTeam(team),
                    usesCircularOutline: team.isNational,
                    size: 18,
                    placeholderSymbolSize: 9
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    func teamNameText(_ team: FootballTeamSummary) -> some View {
        Text(FootballFixtureFormatter.teamDisplayIdentifier(for: team))
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: true, vertical: false)
    }

    func localTeamLogoPath(for team: FootballTeamSummary) -> String? {
        guard !FootballFixtureFormatter.isUnknownTeam(team) else { return nil }
        return monitor.footballLocalLogoPathsByTeamID[team.id]
    }

    func localCompetitionLogoPath(for match: FootballFixtureMatch) -> String? {
        monitor.footballLocalLogoPathsByCompetitionSlug[match.competitionSlug]
    }

    func competitionHeaderLogoSource(
        for section: FootballMenuCompetitionSection
    ) -> (localPath: String?, remoteURL: URL?)? {
        let preferredMatch = section.matches.first(where: { match in
            localCompetitionLogoPath(for: match) != nil || match.competitionLogoURL != nil
        }) ?? displayedMatches(section.matches).first

        guard let preferredMatch else {
            return nil
        }

        return (
            localPath: localCompetitionLogoPath(for: preferredMatch),
            remoteURL: preferredMatch.competitionLogoURL
        )
    }

    func footballCardStatusText(for match: FootballFixtureMatch) -> String? {
        FootballFixtureFormatter.fixtureContextText(for: match)
    }

    func footballCardScheduleText(for match: FootballFixtureMatch) -> String? {
        CalendarMonitor.footballScheduleText(for: match, now: visibleNow)
    }

    func footballCardTrailingBadgeText(for match: FootballFixtureMatch) -> String? {
        CalendarMonitor.footballStatusBadgeText(for: match, now: visibleNow)
    }

    func footballCardTrailingText(for match: FootballFixtureMatch) -> String? {
        if footballCardTrailingBadgeText(for: match) != nil {
            return nil
        }

        switch match.statusState {
        case .scheduled:
            return footballCardScheduleText(for: match)
        case .unknown:
            return monitor.footballMatchStatusText(match)
        case .inProgress, .finished:
            let statusText = monitor.footballMatchStatusText(match)
            return statusText.caseInsensitiveCompare("LIVE") == .orderedSame ? nil : statusText
        }
    }

    func competitionBulkActionButton(for matches: [FootballFixtureMatch]) -> some View {
        let shouldRemoveAll = matches.allSatisfy { managedFootballMatchIDs.contains($0.id) }
        let title = shouldRemoveAll ? "Remove All" : "Add All"
        let systemImage = shouldRemoveAll ? "minus.circle" : "plus.circle"

        return Button {
            Task {
                await applyCompetitionBulkAction(to: matches, shouldRemoveAll: shouldRemoveAll)
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!shouldRemoveAll && footballTargetCalendarID.isEmpty)
    }

    func applyCompetitionBulkAction(
        to matches: [FootballFixtureMatch],
        shouldRemoveAll: Bool
    ) async {
        if shouldRemoveAll {
            for match in matches {
                monitor.removeFootballMatchFromCalendar(match)
            }
        } else {
            for match in matches where !managedFootballMatchIDs.contains(match.id) {
                await monitor.addFootballMatchToCalendar(match)
            }
        }

        let now = Self.minuteReferenceDate(for: AlertCalendarClock.nowRoundedToSecond())
        visibleNow = now
        await refreshManagedMatchesPanel(now: now, force: true)
    }

    func footballCardShowsMetadataLine(_ match: FootballFixtureMatch, showsCompetitionName: Bool) -> Bool {
        footballCardStatusText(for: match) != nil || showsCompetitionName
    }

    func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func loadingState(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func errorState(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func feedbackState(
        title: String,
        text: String,
        systemImage: String,
        tint: Color,
        buttonTitle: String? = nil,
        isButtonDisabled: Bool = false,
        action: (() async -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 16, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let buttonTitle,
               let action {
                Button(buttonTitle) {
                    Task {
                        await action()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isButtonDisabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func minuteReferenceDate(for date: Date) -> Date {
        Calendar.autoupdatingCurrent.dateInterval(of: .minute, for: date)?.start ?? date
    }

    static func nextMinuteBoundary(after date: Date) -> Date {
        Calendar.autoupdatingCurrent.dateInterval(of: .minute, for: date)?.end ?? date.addingTimeInterval(60)
    }


}
