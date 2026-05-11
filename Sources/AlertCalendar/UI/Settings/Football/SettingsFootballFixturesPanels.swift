import AppKit
import Combine
import SwiftUI

extension SettingsFootballFixturesSectionView {
    var addedMatchesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Added Matches")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(upcomingManagedEventCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 16) {
                calendarAlertControlField
                    .frame(maxWidth: 360, alignment: .leading)

                Text(footballCalendarAlertSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let sharedAddedMatchesCompetitionTitle {
                sharedCompetitionHeader(
                    text: "All added matches are from \(sharedAddedMatchesCompetitionTitle)",
                    localLogoPath: sharedAddedMatchesCompetitionLocalLogoPath,
                    remoteLogoURL: sharedAddedMatchesCompetitionLogoURL
                )
            }

            VStack(alignment: .leading, spacing: 0) {
                if isLoadingUpcomingAddedMatches {
                    loadingState("Loading added fixtures...")
                        .padding(.top, 4)
                } else if upcomingManagedMatches.isEmpty {
                    emptyState("Added matches will appear here once you add a fixture.")
                        .padding(.top, 4)
                } else {
                    matchCardsViewport(
                        upcomingManagedMatches,
                        showsCompetitionName: sharedAddedMatchesCompetitionTitle == nil,
                        showsSeparateMetadataRows: true
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelChrome)
    }

    var liveAndNextDayPanel: some View {
        let section = footballLiveAndNextDaySection
        let visibleMatches = displayedLiveAndNextDayMatches

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if section.isLoading && !section.hasLoaded && section.matches.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                } else if section.hasLoaded {
                    Text("\(visibleMatches.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = section.errorMessage {
                feedbackState(
                    title: "Could not load \(section.title)",
                    text: errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange,
                    buttonTitle: "Retry",
                    isButtonDisabled: section.isLoading
                ) {
                    await retryLiveAndNextDayLoad()
                }
            }

            if let sharedLiveAndNextDayCompetitionTitle,
               !visibleMatches.isEmpty {
                sharedCompetitionHeader(
                    text: "All listed matches are from \(sharedLiveAndNextDayCompetitionTitle)",
                    localLogoPath: sharedLiveAndNextDayCompetitionLocalLogoPath,
                    remoteLogoURL: sharedLiveAndNextDayCompetitionLogoURL
                )
            }

            if section.isLoading && !section.hasLoaded && section.matches.isEmpty {
                loadingState("Loading live and upcoming fixtures...")
            } else if !section.hasLoaded && section.matches.isEmpty {
                feedbackState(
                    title: "Nothing loaded yet",
                    text: "Use Retry to fetch live matches and the next 24 hours of fixtures.",
                    systemImage: FootballFixtureFormatter.footballLocationSymbolName,
                    tint: .secondary,
                    buttonTitle: "Retry"
                ) {
                    await retryLiveAndNextDayLoad()
                }
            } else if liveAndNextDayMatchesByRegion.isEmpty {
                emptyState("No upcoming scheduled regional groups are available in the next 24 hours right now.")
            } else {
                liveAndNextDayRegionsContent(
                    liveAndNextDayMatchesByRegion,
                    showsCompetitionName: sharedLiveAndNextDayCompetitionTitle == nil
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelChrome)
    }

    func liveAndNextDayRegionsContent(
        _ entries: [(region: FootballCompetitionRegion, matches: [FootballFixtureMatch])],
        showsCompetitionName: Bool
    ) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(entries.enumerated()), id: \.element.region.id) { index, entry in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(entry.region.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(entry.matches.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        matchCardsGrid(
                            entry.matches,
                            showsCompetitionName: showsCompetitionName,
                            showsSeparateMetadataRows: true
                        )
                    }

                    if index < entries.count - 1 {
                        Divider()
                            .padding(.vertical, 2)
                    }
                }
            }
            .padding(.trailing, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var panelChrome: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    @ViewBuilder
    func matchCardsViewport(
        _ matches: [FootballFixtureMatch],
        showsCompetitionName: Bool,
        showsSeparateMetadataRows: Bool = false
    ) -> some View {
        if matches.count > Self.scrollableMatchCardThreshold {
            ScrollView(.vertical, showsIndicators: true) {
                matchCardsGrid(
                    matches,
                    showsCompetitionName: showsCompetitionName,
                    showsSeparateMetadataRows: showsSeparateMetadataRows
                )
                .padding(.trailing, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            matchCardsGrid(
                matches,
                showsCompetitionName: showsCompetitionName,
                showsSeparateMetadataRows: showsSeparateMetadataRows
            )
        }
    }

    func matchCardsGrid(
        _ matches: [FootballFixtureMatch],
        showsCompetitionName: Bool,
        showsSeparateMetadataRows: Bool = false
    ) -> some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(
                        minimum: Self.minimumMatchCardWidth,
                        maximum: Self.preferredMatchCardWidth
                    ),
                    spacing: 12,
                    alignment: .top
                )
            ],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(matches) { match in
                matchCard(
                    match,
                    showsCompetitionName: showsCompetitionName,
                    showsSeparateMetadataRows: showsSeparateMetadataRows
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func matchCard(
        _ match: FootballFixtureMatch,
        showsCompetitionName: Bool,
        showsSeparateMetadataRows: Bool = false
    ) -> some View {
        FootballMatchCardHoverContainer { isHovered in
            matchCardContent(
                match,
                showsCompetitionName: showsCompetitionName,
                showsSeparateMetadataRows: showsSeparateMetadataRows,
                isHovered: isHovered
            )
        }
    }

    @ViewBuilder
    func matchCardContent(
        _ match: FootballFixtureMatch,
        showsCompetitionName: Bool,
        showsSeparateMetadataRows: Bool,
        isHovered: Bool
    ) -> some View {
        let trailingStatusAccessories = FootballStatusAccessoriesView.accessories(for: match, now: visibleNow)
        let inlineAccessories = FootballStatusAccessoriesData(
            badgeText: nil,
            warningText: trailingStatusAccessories.warningText
        )
        let warningText = CalendarMonitor.footballStatusWarningText(for: match)
        let warningSummary = warningText.flatMap { _ in CalendarMonitor.footballStatusWarningSummary(for: match) }
        let isManaged = managedFootballMatchIDs.contains(match.id)
        let baseBorderColor = isManaged ? Color.green.opacity(0.28) : Color.primary.opacity(0.06)

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                fixtureTitleRow(match, accessories: inlineAccessories)

                Spacer(minLength: 0)

                matchCardTrailingAccessory(match, isHovered: isHovered)
            }

            if showsSeparateMetadataRows {
                matchCardMetadataRows(match, showsCompetitionName: showsCompetitionName)
            } else if footballCardShowsMetadataLine(match, showsCompetitionName: showsCompetitionName) {
                HStack(spacing: 6) {
                    if let statusText = footballCardStatusText(for: match) {
                        Text(statusText)
                    }
                    if showsCompetitionName {
                        competitionInlineLabel(match)
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let warningSummary,
               let warningText {
                Text(warningSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(warningText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHovered ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isHovered ? Color.accentColor.opacity(0.22) : baseBorderColor, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.14), value: isHovered)
    }

    @ViewBuilder
    func matchCardMetadataRows(_ match: FootballFixtureMatch, showsCompetitionName: Bool) -> some View {
        if let scheduleText = footballCardScheduleText(for: match),
           footballCardTrailingText(for: match) == nil,
           footballCardTrailingBadgeText(for: match) == nil {
            matchMetadataRow(scheduleText)
        }

        if let statusText = footballCardStatusText(for: match) {
            matchMetadataRow(statusText)
        }

        if showsCompetitionName {
            competitionMetadataRow(for: match)
        }
    }

    func matchMetadataRow(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func competitionMetadataRow(for match: FootballFixtureMatch) -> some View {
        HStack(spacing: 6) {
            FootballCompetitionLogoView(
                localPath: localCompetitionLogoPath(for: match),
                remoteURL: match.competitionLogoURL
            )
            Text(FootballFixtureFormatter.competitionDetailText(for: match))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func competitionInlineLabel(_ match: FootballFixtureMatch) -> some View {
        HStack(spacing: 6) {
            FootballCompetitionLogoView(
                localPath: localCompetitionLogoPath(for: match),
                remoteURL: match.competitionLogoURL
            )
            Text(match.competitionName)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    func sharedCompetitionHeader(text: String, localLogoPath: String?, remoteLogoURL: URL?) -> some View {
        HStack(spacing: 6) {
            FootballCompetitionLogoView(localPath: localLogoPath, remoteURL: remoteLogoURL)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

}

private struct FootballMatchCardHoverContainer<Content: View>: View {
    let content: (Bool) -> Content
    @State private var isHovered = false

    init(@ViewBuilder content: @escaping (Bool) -> Content) {
        self.content = content
    }

    var body: some View {
        content(isHovered)
            .onHover { hovering in
                guard isHovered != hovering else { return }
                isHovered = hovering
            }
    }
}
