import AppKit
import SwiftUI

struct SettingsFootballFixturesSectionView: View {
    private enum FootballBrowseMode: String, CaseIterable, Identifiable {
        case competitions = "Competitions"
        case liveAndNextDay = "Live + 48h"

        var id: String { rawValue }
    }

    @ObservedObject var monitor: CalendarMonitor

    @AppStorage(DefaultsKeys.footballTargetCalendarID) private var footballTargetCalendarID = ""
    @AppStorage(DefaultsKeys.footballCalendarAlertOption) private var footballCalendarAlertOptionRaw = FootballCalendarAlertOption.none.rawValue
    @State private var browseMode: FootballBrowseMode = .competitions
    @State private var expandedCompetitionIDs: Set<String> = []
    @State private var competitionListHeight: CGFloat = 0
    @State private var addedMatchesContentHeight: CGFloat = 0
    @State private var isRefreshingManagedMatches = false
    @State private var visibleNow = Date()

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
                    footballContentSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            visibleNow = Self.minuteReferenceDate(for: Date())
            if footballTargetCalendarID.isEmpty,
               let resolvedCalendarID = monitor.footballTargetCalendarID() {
                footballTargetCalendarID = resolvedCalendarID
            }
            monitor.ensureFootballCompetitionSections()
            monitor.refreshManagedFootballTrackingSnapshot(now: visibleNow)
        }
        .task(id: browseMode) {
            guard browseMode == .liveAndNextDay else { return }
            await monitor.loadFootballLiveAndNextDaySection(force: true)
        }
        .task {
            await refreshManagedMatchesPanel(now: visibleNow)
        }
        .task {
            await runVisibleRefreshLoop()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            let now = Self.minuteReferenceDate(for: Date())
            visibleNow = now
            monitor.refreshManagedFootballTrackingSnapshot(now: now)
            Task {
                if browseMode == .liveAndNextDay {
                    await monitor.loadFootballLiveAndNextDaySection(force: true)
                }
                await refreshManagedMatchesPanel(now: now)
            }
        }
        .onChange(of: footballCalendarAlertOptionRaw) { _ in
            applyFootballCalendarAlertPreference()
        }
    }

    private var footballContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            footballTopControlsSection
            addedMatchesPanel

            if browseMode == .competitions && monitor.footballMenuSections.isEmpty {
                emptyState("No competitions are configured right now.")
            } else {
                activeMatchesPanel
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .onPreferenceChange(FootballFixturesPanelHeightPreferenceKey.self) { newHeight in
            guard abs(newHeight - competitionListHeight) > 0.5 else { return }
            competitionListHeight = newHeight
        }
    }

    private var writableCalendars: [AvailableCalendar] {
        monitor.writableFootballTargetCalendars()
    }

    private var footballCalendarAlertOption: FootballCalendarAlertOption {
        FootballCalendarAlertOption(rawValue: footballCalendarAlertOptionRaw) ?? .none
    }

    private var footballCalendarAlertOptionBinding: Binding<FootballCalendarAlertOption> {
        Binding(
            get: { footballCalendarAlertOption },
            set: { footballCalendarAlertOptionRaw = $0.rawValue }
        )
    }

    private var footballCalendarAlertSummaryText: String {
        if footballCalendarAlertOption == .none {
            return "Managed football fixtures will be added without an Apple Calendar alert."
        }
        return "All managed football fixtures use the same Apple Calendar alert: \(footballCalendarAlertOption.title.lowercased())."
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
        CalendarMonitor.upcomingManagedFootballMatches(from: monitor.managedFootballMatches, now: visibleNow)
    }

    private var upcomingManagedEventCount: Int {
        monitor.upcomingManagedFootballEventCount(now: visibleNow)
    }

    private var hasUpcomingAddedMatches: Bool {
        upcomingManagedEventCount > 0
    }

    private var isLoadingUpcomingAddedMatches: Bool {
        hasUpcomingAddedMatches && upcomingManagedMatches.isEmpty && isRefreshingManagedMatches
    }

    private var sharedAddedMatchesCompetitionTitle: String? {
        FootballFixtureFormatter.sharedCompetitionTitle(for: upcomingManagedMatches)
    }

    private var sharedAddedMatchesCompetitionLogoURL: URL? {
        guard sharedAddedMatchesCompetitionTitle != nil else { return nil }
        return upcomingManagedMatches.first?.competitionLogoURL
    }

    private var sharedLiveAndNextDayCompetitionTitle: String? {
        FootballFixtureFormatter.sharedCompetitionTitle(for: monitor.footballLiveAndNextDaySection.matches)
    }

    private var sharedLiveAndNextDayCompetitionLogoURL: URL? {
        guard sharedLiveAndNextDayCompetitionTitle != nil else { return nil }
        return monitor.footballLiveAndNextDaySection.matches.first?.competitionLogoURL
    }

    private var liveAndNextDayMatchesByCategory: [(category: FootballCompetitionCategory, matches: [FootballFixtureMatch])] {
        FootballCompetitionCategory.allCases.compactMap { category in
            let matches = monitor.footballLiveAndNextDaySection.matches.filter { $0.competitionCategory == category }
            guard !matches.isEmpty else { return nil }
            return (category, matches)
        }
    }

    private var footballTopControlsSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                footballPrimaryControlsSection
                    .frame(maxWidth: .infinity, alignment: .leading)
                if hasUpcomingAddedMatches {
                    footballManagedMatchesSection
                        .frame(minWidth: 320, idealWidth: 352, maxWidth: 384, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                footballPrimaryControlsSection
                if hasUpcomingAddedMatches {
                    footballManagedMatchesSection
                }
            }
        }
    }

    private var footballPrimaryControlsSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                addToControlField
                    .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

                showControlField
                    .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 12) {
                addToControlField
                showControlField
            }
        }
    }

    private var footballManagedMatchesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            calendarAlertControlField

            Text(footballCalendarAlertSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var measuredAddedMatchesContentHeight: CGFloat? {
        addedMatchesContentHeight > 0 ? addedMatchesContentHeight : nil
    }

    private var addToControlField: some View {
        footballControlField(
            title: "Add To",
            helpText: "This calendar is used when you add a football fixture from the list below."
        ) {
            Picker("Add fixtures to calendar", selection: $footballTargetCalendarID) {
                ForEach(writableCalendars) { calendar in
                    Text(calendar.title).tag(calendar.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var showControlField: some View {
        footballControlField(title: "Show") {
            Picker("Football view", selection: $browseMode) {
                ForEach(FootballBrowseMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var calendarAlertControlField: some View {
        footballControlField(
            title: "Calendar Alert",
            helpText: "Applies the same Apple Calendar alert to every football fixture managed by Alert Calendar, including ones already added."
        ) {
            Picker("Football event alert", selection: footballCalendarAlertOptionBinding) {
                ForEach(FootballCalendarAlertOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private func footballControlField<Control: View>(
        title: String,
        helpText: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                if let helpText {
                    InfoTipButton(text: helpText)
                }
            }
            .font(.subheadline.weight(.medium))

            control()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var competitionListPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            competitionCategorySection(
                title: FootballCompetitionCategory.clubCompetitions.title,
                sections: monitor.footballMenuSections.filter { $0.competition.category == .clubCompetitions }
            )

            if !monitor.footballMenuSections.filter({ $0.competition.category == .nationalTeams }).isEmpty {
                Divider()
                    .padding(.vertical, 2)
            }

            competitionCategorySection(
                title: FootballCompetitionCategory.nationalTeams.title,
                sections: monitor.footballMenuSections.filter { $0.competition.category == .nationalTeams }
            )
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

    @ViewBuilder
    private func competitionCategorySection(
        title: String,
        sections: [FootballMenuCompetitionSection]
    ) -> some View {
        if !sections.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(sections) { section in
                    competitionDisclosure(section)
                }
            }
        }
    }

    private func competitionDisclosure(_ section: FootballMenuCompetitionSection) -> some View {
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

            if let sharedAddedMatchesCompetitionTitle {
                sharedCompetitionHeader(
                    text: "All added matches are from \(sharedAddedMatchesCompetitionTitle)",
                    logoURL: sharedAddedMatchesCompetitionLogoURL
                )
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if isLoadingUpcomingAddedMatches {
                        loadingState("Loading added fixtures...")
                            .padding(.top, 4)
                    } else if upcomingManagedMatches.isEmpty {
                        emptyState("Added matches will appear here once you add a fixture.")
                            .padding(.top, 4)
                    } else {
                        LazyVGrid(columns: matchGridColumns, alignment: .leading, spacing: 12) {
                            ForEach(upcomingManagedMatches) { match in
                                matchCard(
                                    match,
                                    showsCompetitionName: sharedAddedMatchesCompetitionTitle == nil,
                                    showsSeparateMetadataRows: true
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: AddedMatchesContentHeightPreferenceKey.self, value: proxy.size.height)
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: measuredAddedMatchesContentHeight, alignment: .topLeading)
            .onPreferenceChange(AddedMatchesContentHeightPreferenceKey.self) { newHeight in
                guard abs(newHeight - addedMatchesContentHeight) > 0.5 else { return }
                addedMatchesContentHeight = newHeight
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

            if let sharedLiveAndNextDayCompetitionTitle {
                sharedCompetitionHeader(
                    text: "All listed matches are from \(sharedLiveAndNextDayCompetitionTitle)",
                    logoURL: sharedLiveAndNextDayCompetitionLogoURL
                )
            }

            if section.isLoading && !section.hasLoaded && section.matches.isEmpty {
                loadingState("Loading live and 48-hour fixtures...")
            } else if section.matches.isEmpty {
                emptyState("No live matches or fixtures in the next 48 hours are available right now.")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(liveAndNextDayMatchesByCategory.enumerated()), id: \.element.category.id) { index, entry in
                        liveMatchesCategorySection(
                            title: entry.category.title,
                            matches: entry.matches,
                            showsCompetitionName: sharedLiveAndNextDayCompetitionTitle == nil
                        )

                        if index < liveAndNextDayMatchesByCategory.count - 1 {
                            Divider()
                                .padding(.vertical, 2)
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

    private func liveMatchesCategorySection(
        title: String,
        matches: [FootballFixtureMatch],
        showsCompetitionName: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(matches.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: matchGridColumns, alignment: .leading, spacing: 12) {
                ForEach(matches) { match in
                    matchCard(
                        match,
                        showsCompetitionName: showsCompetitionName,
                        showsSeparateMetadataRows: true
                    )
                }
            }
        }
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
    private func matchCard(
        _ match: FootballFixtureMatch,
        showsCompetitionName: Bool,
        showsSeparateMetadataRows: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                fixtureTitleRow(match)

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
    private func matchCardMetadataRows(_ match: FootballFixtureMatch, showsCompetitionName: Bool) -> some View {
        if let scheduleText = footballCardScheduleText(for: match) {
            matchMetadataRow(scheduleText)
        }

        if showsCompetitionName {
            competitionMetadataRow(for: match)
        }
    }

    private func matchMetadataRow(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func competitionMetadataRow(for match: FootballFixtureMatch) -> some View {
        HStack(spacing: 6) {
            competitionLogo(url: match.competitionLogoURL)
            Text(footballCompetitionDetailText(match))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func competitionInlineLabel(_ match: FootballFixtureMatch) -> some View {
        HStack(spacing: 6) {
            competitionLogo(url: match.competitionLogoURL)
            Text(match.competitionName)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func sharedCompetitionHeader(text: String, logoURL: URL?) -> some View {
        HStack(spacing: 6) {
            competitionLogo(url: logoURL)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
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

                    if footballHasStatusAccessories(for: match) {
                        Spacer(minLength: 8)
                        footballStatusAccessories(for: match)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

                teamLabelRow(match.awayTeam, logoLeading: true)
            }
        }
    }

    private func fixtureTitleLine(_ match: FootballFixtureMatch) -> some View {
        HStack(alignment: .center, spacing: 6) {
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
            }
            .fixedSize(horizontal: true, vertical: false)

            if footballHasStatusAccessories(for: match) {
                Spacer(minLength: 8)
                footballStatusAccessories(for: match)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    private func competitionLogo(url: URL?) -> some View {
        AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "trophy")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 14, height: 14)
    }

    private func safeScore(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "0" : trimmed
    }

    private func footballStatusBadge(text: String) -> some View {
        let tint = Color(nsColor: CalendarMonitor.footballStatusTintColor(for: text))

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

    @ViewBuilder
    private func footballStatusAccessories(for match: FootballFixtureMatch) -> some View {
        if let badgeText = CalendarMonitor.footballStatusBadgeText(for: match, now: visibleNow) {
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

    private func footballHasStatusAccessories(for match: FootballFixtureMatch) -> Bool {
        CalendarMonitor.footballStatusBadgeText(for: match, now: visibleNow) != nil
            || CalendarMonitor.footballStatusWarningText(for: match) != nil
    }

    private func footballCardStatusText(for match: FootballFixtureMatch) -> String? {
        if match.hasInterruptedStatus {
            return nil
        }

        if match.statusState == .inProgress || match.statusState == .finished {
            return CalendarMonitor.footballStartedStatusText(
                for: match.actualStartDate ?? match.startDate,
                now: visibleNow
            )
        }
        if CalendarMonitor.footballStatusBadgeText(for: match, now: visibleNow) != nil {
            return nil
        }
        return monitor.footballMatchStatusText(match)
    }

    private func footballCardScheduleText(for match: FootballFixtureMatch) -> String? {
        if match.hasInterruptedStatus {
            return CalendarMonitor.footballKickoffStatusText(for: match.startDate, now: visibleNow)
        }

        if match.statusState == .inProgress || match.statusState == .finished {
            return CalendarMonitor.footballStartedStatusText(
                for: match.actualStartDate ?? match.startDate,
                now: visibleNow
            )
        }

        return CalendarMonitor.footballKickoffStatusText(for: match.startDate, now: visibleNow)
    }

    private func footballCompetitionDetailText(_ match: FootballFixtureMatch) -> String {
        FootballFixtureFormatter.competitionDetailText(
            competitionName: match.competitionName,
            competitionStage: match.competitionStage
        )
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

    private static func minuteReferenceDate(for date: Date) -> Date {
        Calendar.autoupdatingCurrent.dateInterval(of: .minute, for: date)?.start ?? date
    }

    private static func nextMinuteBoundary(after date: Date) -> Date {
        Calendar.autoupdatingCurrent.dateInterval(of: .minute, for: date)?.end ?? date.addingTimeInterval(60)
    }

    private func applyFootballCalendarAlertPreference() {
        let now = Self.minuteReferenceDate(for: Date())
        visibleNow = now
        monitor.applyManagedFootballAlertConfigurationIfNeeded(now: now)
        monitor.refreshManagedFootballTrackingSnapshot(now: now)
    }

    private func runVisibleRefreshLoop() async {
        while !Task.isCancelled {
            let now = Date()
            let nextRefresh = Self.nextMinuteBoundary(after: now)
            let delay = max(0.25, nextRefresh.timeIntervalSince(now))
            let delayNanoseconds = UInt64(delay * 1_000_000_000)

            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }

            let refreshedNow = Self.minuteReferenceDate(for: Date())
            await MainActor.run {
                visibleNow = refreshedNow
                monitor.refreshManagedFootballTrackingSnapshot(now: refreshedNow)
            }

            if browseMode == .liveAndNextDay {
                await monitor.loadFootballLiveAndNextDaySection(force: true)
            }
            await refreshManagedMatchesPanel(now: refreshedNow)
        }
    }

    @MainActor
    private func refreshManagedMatchesPanel(now: Date) async {
        isRefreshingManagedMatches = true
        defer { isRefreshingManagedMatches = false }
        await monitor.syncManagedFootballEventsIfNeeded(now: now)
    }
}

private struct FootballFixturesPanelHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct AddedMatchesContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
