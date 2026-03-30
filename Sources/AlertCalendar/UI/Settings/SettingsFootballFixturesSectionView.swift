import AppKit
import SwiftUI

struct SettingsFootballFixturesSectionView: View {
    private enum FootballBrowseMode: String, CaseIterable, Identifiable {
        case competitions = "All Leagues"
        case liveAndNextDay = "Live + 48h"

        var id: String { rawValue }
    }

    @ObservedObject var monitor: CalendarMonitor

    @AppStorage(DefaultsKeys.footballTargetCalendarID) private var footballTargetCalendarID = ""
    @State private var browseMode: FootballBrowseMode = .competitions
    @State private var expandedCompetitionIDs: Set<String> = []
    @State private var competitionListHeight: CGFloat = 0
    @State private var isRefreshingManagedMatches = false

    private let matchGridColumns = [
        GridItem(.adaptive(minimum: 280, maximum: 340), spacing: 12, alignment: .top),
    ]

    var body: some View {
        GroupBox("Football Fixtures") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add supported football matches to an Apple Calendar managed by Alert Calendar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Suggestions only include matches from the last 30 days and next 30 days. If a managed fixture falls outside that window, Alert Calendar removes it automatically from Apple Calendar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !monitor.hasEventsAccess {
                    emptyState("Grant Calendar access to add football fixtures.")
                } else if writableCalendars.isEmpty {
                    emptyState("No writable event calendars are available.")
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        HStack(spacing: 6) {
                            Text("Add To")
                            InfoTipButton(text: "This calendar is used when you add a football fixture from the list below.")
                        }
                        .font(.subheadline.weight(.medium))

                        Spacer(minLength: 12)

                        Picker("Add fixtures to calendar", selection: $footballTargetCalendarID) {
                            ForEach(writableCalendars) { calendar in
                                Text(calendar.title).tag(calendar.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 240)
                    }

                    HStack(alignment: .center, spacing: 12) {
                        Text("Show")
                            .font(.subheadline.weight(.medium))

                        Spacer(minLength: 12)

                        Picker("Football view", selection: $browseMode) {
                            ForEach(FootballBrowseMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 320)
                    }

                    fixtureColumns
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if footballTargetCalendarID.isEmpty,
               let resolvedCalendarID = monitor.footballTargetCalendarID() {
                footballTargetCalendarID = resolvedCalendarID
            }
            monitor.ensureFootballCompetitionSections()
            monitor.refreshManagedFootballTrackingSnapshot(now: Date())
        }
        .task(id: browseMode) {
            guard browseMode == .liveAndNextDay else { return }
            await monitor.loadFootballLiveAndNextDaySection(force: true)
        }
        .task {
            await refreshManagedMatchesPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            monitor.refreshManagedFootballTrackingSnapshot(now: Date())
            Task {
                await refreshManagedMatchesPanel()
            }
        }
    }

    @ViewBuilder
    private var fixtureColumns: some View {
        if browseMode == .competitions && monitor.footballMenuSections.isEmpty {
            emptyState("No competitions are configured right now.")
        } else {
            HStack(alignment: .top, spacing: 16) {
                activeMatchesPanel
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                if hasUpcomingAddedMatches {
                    addedMatchesPanel
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .onPreferenceChange(FootballFixturesPanelHeightPreferenceKey.self) { newHeight in
                guard abs(newHeight - competitionListHeight) > 0.5 else { return }
                competitionListHeight = newHeight
            }
        }
    }

    private var writableCalendars: [AvailableCalendar] {
        monitor.writableFootballTargetCalendars()
    }

    private var activeMatchesPanel: some View {
        Group {
            switch browseMode {
            case .competitions:
                competitionListPanel
            case .liveAndNextDay:
                liveAndNextDayPanel
            }
        }
    }

    private var upcomingManagedMatches: [FootballFixtureMatch] {
        CalendarMonitor.upcomingManagedFootballMatches(from: monitor.managedFootballMatches, now: Date())
    }

    private var upcomingManagedEventCount: Int {
        monitor.upcomingManagedFootballEventCount(now: Date())
    }

    private var hasUpcomingAddedMatches: Bool {
        upcomingManagedEventCount > 0
    }

    private var isLoadingUpcomingAddedMatches: Bool {
        hasUpcomingAddedMatches && upcomingManagedMatches.isEmpty && isRefreshingManagedMatches
    }

    private var measuredCompetitionListHeight: CGFloat? {
        competitionListHeight > 0 ? competitionListHeight : nil
    }

    private var competitionListPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(monitor.footballMenuSections) { section in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedCompetitionIDs.contains(section.id) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedCompetitionIDs.insert(section.id)
                                Task {
                                    await monitor.loadFootballCompetitionSection(section.competition, force: true)
                                }
                            } else {
                                expandedCompetitionIDs.remove(section.id)
                            }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        if section.isLoading && !section.hasLoaded && section.matches.isEmpty {
                            loadingState("Loading fixtures for \(section.competition.title)...")
                        } else if let errorMessage = section.errorMessage {
                            errorState(errorMessage)
                        }

                        if !section.hasLoaded && !section.isLoading && section.matches.isEmpty {
                            emptyState("Click this competition to load its matches.")
                        } else if section.matches.isEmpty {
                            emptyState("No matches available in the last or next 30 days.")
                        } else {
                            LazyVGrid(columns: matchGridColumns, alignment: .leading, spacing: 12) {
                                ForEach(section.matches) { match in
                                    matchCard(match, showsCompetitionName: false)
                                }
                            }
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    HStack(spacing: 8) {
                        Text(section.competition.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        if section.isLoading && !section.hasLoaded && section.matches.isEmpty {
                            ProgressView()
                                .controlSize(.small)
                        } else if section.hasLoaded {
                            Text("\(section.matches.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Load")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(panelChrome)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: FootballFixturesPanelHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
    }

    private var addedMatchesPanel: some View {
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

            ScrollView(.vertical, showsIndicators: true) {
                if isLoadingUpcomingAddedMatches {
                    loadingState("Loading added fixtures...")
                        .padding(.top, 4)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(upcomingManagedMatches) { match in
                            matchCard(match, showsCompetitionName: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(14)
        .frame(minWidth: 320, idealWidth: 352, maxWidth: 384, alignment: .topLeading)
        .frame(height: measuredCompetitionListHeight, alignment: .topLeading)
        .background(panelChrome)
    }

    private var liveAndNextDayPanel: some View {
        let section = monitor.footballLiveAndNextDaySection

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
                    Text("\(section.matches.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = section.errorMessage {
                errorState(errorMessage)
            }

            if section.isLoading && !section.hasLoaded && section.matches.isEmpty {
                loadingState("Loading live and 48-hour fixtures...")
            } else if section.matches.isEmpty {
                emptyState("No live matches or fixtures in the next 48 hours are available right now.")
            } else {
                LazyVGrid(columns: matchGridColumns, alignment: .leading, spacing: 12) {
                    ForEach(section.matches) { match in
                        matchCard(match, showsCompetitionName: true)
                    }
                }
            }
        }
        .padding(14)
        .background(panelChrome)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: FootballFixturesPanelHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
    }

    private var panelChrome: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func matchCard(_ match: FootballFixtureMatch, showsCompetitionName: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                fixtureTitleRow(match)

                if footballCardShowsMetadataLine(match, showsCompetitionName: showsCompetitionName) {
                    HStack(spacing: 6) {
                        if let statusText = footballCardStatusText(for: match) {
                            Text(statusText)
                        }
                        if showsCompetitionName {
                            Text(match.competitionName)
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                if let warningSummary = CalendarMonitor.footballStatusWarningSummary(for: match),
                   let warningText = CalendarMonitor.footballStatusWarningText(for: match) {
                    Text(warningSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(warningText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            matchCardActions(match)
                .frame(alignment: .topTrailing)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    @ViewBuilder
    private func matchCardActions(_ match: FootballFixtureMatch) -> some View {
        if monitor.isFootballMatchTracked(match) {
            HStack(spacing: 8) {
                openMatchButton(match)
                removeMatchButton(match)
            }
        } else {
            actionIconButton(
                systemName: "plus",
                tint: .green,
                helpText: "Add this event to Apple Calendar"
            ) {
                Task {
                    await monitor.addFootballMatchToCalendar(match)
                }
            }
            .disabled(footballTargetCalendarID.isEmpty)
        }
    }

    private func openMatchButton(_ match: FootballFixtureMatch) -> some View {
        actionIconButton(
            systemName: "arrow.up.forward.app",
            tint: .accentColor,
            helpText: "Open this event in Apple Calendar"
        ) {
            monitor.openFootballMatchInCalendar(match)
        }
    }

    private func removeMatchButton(_ match: FootballFixtureMatch) -> some View {
        actionIconButton(
            systemName: "minus",
            tint: .red,
            helpText: "Remove this event from Apple Calendar"
        ) {
            monitor.removeFootballMatchFromCalendar(match)
        }
    }

    private func actionIconButton(
        systemName: String,
        tint: Color,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(tint.opacity(0.28), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    @ViewBuilder
    private func fixtureTitleRow(_ match: FootballFixtureMatch) -> some View {
        ViewThatFits(in: .horizontal) {
            fixtureTitleLine(match)

            VStack(alignment: .leading, spacing: 4) {
                teamLabelRow(match.homeTeam, logoLeading: false)

                HStack(spacing: 6) {
                    if match.hasVisibleScore {
                        Text("\(safeScore(match.homeScore)) - \(safeScore(match.awayScore))")
                    } else {
                        Text("-")
                    }

                    footballStatusAccessories(for: match)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

                teamLabelRow(match.awayTeam, logoLeading: true)
            }
        }
    }

    private func fixtureTitleLine(_ match: FootballFixtureMatch) -> some View {
        HStack(alignment: .center, spacing: 6) {
            teamLabelRow(match.homeTeam, logoLeading: false)

            if match.hasVisibleScore {
                Text(safeScore(match.homeScore))
                    .frame(minWidth: 10, alignment: .center)
            }

            Text("-")
                .foregroundStyle(.secondary)

            if match.hasVisibleScore {
                Text(safeScore(match.awayScore))
                    .frame(minWidth: 10, alignment: .center)
            }

            teamLabelRow(match.awayTeam, logoLeading: true)

            footballStatusAccessories(for: match)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func teamLabelRow(_ team: FootballTeamSummary, logoLeading: Bool) -> some View {
        HStack(spacing: 4) {
            if logoLeading {
                teamLogo(url: FootballFixtureFormatter.isUnknownTeam(team) ? nil : team.logoURL)
                Text(FootballFixtureFormatter.teamDisplayIdentifier(for: team))
            } else {
                Text(FootballFixtureFormatter.teamDisplayIdentifier(for: team))
                teamLogo(url: FootballFixtureFormatter.isUnknownTeam(team) ? nil : team.logoURL)
            }
        }
    }

    @ViewBuilder
    private func teamLogo(url: URL?) -> some View {
        AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(
                        Image(systemName: "shield")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: 18, height: 18)
    }

    private func safeScore(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "0" : trimmed
    }

    private func footballStatusBadge(text: String) -> some View {
        let tint = footballStatusBadgeTint(for: text)

        return Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.16))
            )
    }

    private func footballStatusBadgeTint(for text: String) -> Color {
        let normalized = text.uppercased()
        if normalized == "FT" {
            return .gray
        }
        if normalized.contains("AET") {
            return .purple
        }
        if normalized.contains("PEN") || normalized == "PK" {
            return .red
        }
        if normalized == "HT" {
            return .orange
        }
        if normalized == "ET" {
            return .indigo
        }
        if normalized == "SOON" {
            return .blue
        }
        return .green
    }

    @ViewBuilder
    private func footballStatusAccessories(for match: FootballFixtureMatch) -> some View {
        if let badgeText = CalendarMonitor.footballStatusBadgeText(for: match) {
            footballStatusBadge(text: badgeText)
        }

        if let warningText = CalendarMonitor.footballStatusWarningText(for: match) {
            footballStatusWarningIcon(helpText: warningText)
        }
    }

    private func footballStatusWarningIcon(helpText: String) -> some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.orange)
            .help(helpText)
    }

    private func footballCardStatusText(for match: FootballFixtureMatch) -> String? {
        if match.statusState == .inProgress || match.statusState == .finished {
            return CalendarMonitor.footballStartedStatusText(for: match.startDate)
        }
        if CalendarMonitor.footballStatusBadgeText(for: match) != nil {
            return nil
        }
        return monitor.footballMatchStatusText(match)
    }

    private func footballCardShowsMetadataLine(_ match: FootballFixtureMatch, showsCompetitionName: Bool) -> Bool {
        footballCardStatusText(for: match) != nil || showsCompetitionName
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadingState(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorState(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func refreshManagedMatchesPanel() async {
        isRefreshingManagedMatches = true
        defer { isRefreshingManagedMatches = false }
        await monitor.syncManagedFootballEventsIfNeeded(now: Date())
    }
}

private struct FootballFixturesPanelHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
