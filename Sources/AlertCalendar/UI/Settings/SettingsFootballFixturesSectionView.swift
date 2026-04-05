import AppKit
import Combine
import SwiftUI

struct SettingsFootballFixturesSectionView: View {
    private enum FootballBrowseMode: String, CaseIterable, Identifiable {
        case competitions = "Competitions"
        case liveAndNextDay = "Now + Next 24h"

        var id: String { rawValue }
    }

    let monitor: CalendarMonitor

    @AppStorage(DefaultsKeys.footballTargetCalendarID) private var footballTargetCalendarID = ""
    @AppStorage(DefaultsKeys.footballCalendarAlertOption) private var footballCalendarAlertOptionRaw = FootballCalendarAlertOption.none.rawValue
    @State private var browseMode: FootballBrowseMode = .competitions
    @State private var expandedCompetitionIDs: Set<String> = []
    @State private var isRefreshingManagedMatches = false
    @State private var visibleNow = Date()
    @State private var hasEventsAccess = false
    @State private var availableEventCalendars: [AvailableCalendar] = []
    @State private var writableEventCalendars: [AvailableCalendar] = []
    @State private var footballMenuSections: [FootballMenuCompetitionSection] = []
    @State private var footballLiveAndNextDaySection = FootballMatchesOverviewSection.placeholder(title: "Now & Next 24 Hours")
    @State private var managedFootballMatchIDs: Set<String> = []
    @State private var managedFootballMatches: [FootballFixtureMatch] = []

    private let matchGridColumns = [
        GridItem(.adaptive(minimum: 280, maximum: 340), spacing: 12, alignment: .top),
    ]

    var body: some View {
        GroupBox("Football Fixtures") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add supported football matches to an Apple Calendar managed by Alert Calendar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Suggestions only include matches from the \(FootballCompetitionPreset.suggestionWindowDescription). If a managed fixture falls outside that window, Alert Calendar removes it automatically from Apple Calendar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !hasEventsAccess {
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
            synchronizeViewStateFromMonitor()
        }
        .task(id: browseMode) {
            guard browseMode == .liveAndNextDay else { return }
            await monitor.loadFootballLiveAndNextDaySection(force: true)
        }
        .task {
            await refreshManagedMatchesPanel(now: visibleNow, force: true)
        }
        .task {
            await runVisibleRefreshLoop()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            let now = Self.minuteReferenceDate(for: Date())
            visibleNow = now
            Task {
                if shouldRefreshManagedMatchesOnVisibleTick {
                    await MainActor.run {
                        monitor.refreshManagedFootballTrackingSnapshot(now: now)
                    }
                }
                if browseMode == .liveAndNextDay {
                    await monitor.loadFootballLiveAndNextDaySection(force: true)
                }
                if shouldRefreshManagedMatchesOnVisibleTick {
                    await refreshManagedMatchesPanel(now: now)
                }
            }
        }
        .onChange(of: footballCalendarAlertOptionRaw) { _ in
            applyFootballCalendarAlertPreference()
        }
        .onReceive(monitor.$hasEventsAccess.removeDuplicates()) { value in
            hasEventsAccess = value
            refreshWritableCalendars()
        }
        .onReceive(monitor.$availableEventCalendars.removeDuplicates()) { calendars in
            availableEventCalendars = calendars
            refreshWritableCalendars()
        }
        .onReceive(monitor.$footballMenuSections.removeDuplicates()) { sections in
            footballMenuSections = sections
        }
        .onReceive(monitor.$footballLiveAndNextDaySection.removeDuplicates()) { section in
            footballLiveAndNextDaySection = section
        }
        .onReceive(monitor.$managedFootballMatchIDs.removeDuplicates()) { ids in
            managedFootballMatchIDs = ids
        }
        .onReceive(monitor.$managedFootballMatches.removeDuplicates()) { matches in
            managedFootballMatches = matches
        }
    }

    private var footballContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            footballTopControlsSection
            addedMatchesPanel

            if browseMode == .competitions && footballMenuSections.isEmpty {
                emptyState("No competitions are configured right now.")
            } else {
                activeMatchesPanel
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var writableCalendars: [AvailableCalendar] {
        writableEventCalendars
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
        CalendarMonitor.upcomingManagedFootballMatches(from: managedFootballMatches, now: visibleNow)
    }

    private var upcomingManagedEventCount: Int {
        upcomingManagedMatches.count
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

    private var sharedAddedMatchesCompetitionLocalLogoPath: String? {
        guard let match = upcomingManagedMatches.first,
              sharedAddedMatchesCompetitionTitle != nil else { return nil }
        return localCompetitionLogoPath(for: match)
    }

    private var sharedLiveAndNextDayCompetitionTitle: String? {
        FootballFixtureFormatter.sharedCompetitionTitle(for: footballLiveAndNextDaySection.matches)
    }

    private var sharedLiveAndNextDayCompetitionLogoURL: URL? {
        guard sharedLiveAndNextDayCompetitionTitle != nil else { return nil }
        return footballLiveAndNextDaySection.matches.first?.competitionLogoURL
    }

    private var sharedLiveAndNextDayCompetitionLocalLogoPath: String? {
        guard let match = footballLiveAndNextDaySection.matches.first,
              sharedLiveAndNextDayCompetitionTitle != nil else { return nil }
        return localCompetitionLogoPath(for: match)
    }

    private var competitionSectionsByRegion: [(region: FootballCompetitionRegion, sections: [FootballMenuCompetitionSection])] {
        FootballCompetitionRegion.allCases.compactMap { region in
            let sections = footballMenuSections.filter { $0.competition.region == region }
            guard !sections.isEmpty else { return nil }
            return (region, sections)
        }
    }

    private var liveAndNextDayMatchesByRegion: [(region: FootballCompetitionRegion, matches: [FootballFixtureMatch])] {
        FootballCompetitionRegion.allCases.compactMap { region in
            let matches = footballLiveAndNextDaySection.matches.filter { $0.competitionRegion == region }
            guard !matches.isEmpty else { return nil }
            return (region, matches)
        }
    }

    private var competitionSectionsWithErrors: [FootballMenuCompetitionSection] {
        footballMenuSections.filter { $0.errorMessage != nil }
    }

    private var hasAnyCompetitionCards: Bool {
        footballMenuSections.contains { !$0.matches.isEmpty }
    }

    private var hasAttemptedCompetitionLoads: Bool {
        footballMenuSections.contains { $0.hasLoaded || $0.isLoading || $0.errorMessage != nil }
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
            competitionListFeedback

            ForEach(Array(competitionSectionsByRegion.enumerated()), id: \.element.region.id) { index, entry in
                competitionRegionSection(
                    title: entry.region.title,
                    sections: entry.sections
                )

                if index < competitionSectionsByRegion.count - 1 {
                    Divider()
                        .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .background(panelChrome)
    }

    @ViewBuilder
    private var competitionListFeedback: some View {
        if !hasAnyCompetitionCards && !competitionSectionsWithErrors.isEmpty {
            feedbackState(
                title: "Could not load football fixtures",
                text: competitionRetryMessage,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                buttonTitle: "Retry Failed Loads",
                isButtonDisabled: footballMenuSections.contains(where: \.isLoading)
            ) {
                await retryFailedCompetitionLoads()
            }
        } else if !hasAnyCompetitionCards && !hasAttemptedCompetitionLoads {
            feedbackState(
                title: "No football cards loaded yet",
                text: "Expand a competition below to load its matches. If a request fails, you will see a retry button in that section.",
                systemImage: "sportscourt",
                tint: .secondary
            )
        }
    }

    private var competitionRetryMessage: String {
        if competitionSectionsWithErrors.count == 1,
           let errorMessage = competitionSectionsWithErrors.first?.errorMessage {
            return errorMessage
        }

        return "Several competitions could not be loaded right now. Try again in a moment."
    }

    @ViewBuilder
    private func competitionRegionSection(
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
                            await loadCompetitionFixtures(section)
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
                    feedbackState(
                        title: "Could not load \(section.competition.title)",
                        text: errorMessage,
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .orange,
                        buttonTitle: "Retry",
                        isButtonDisabled: section.isLoading
                    ) {
                        await loadCompetitionFixtures(section)
                    }
                }

                if !section.hasLoaded && !section.isLoading && section.matches.isEmpty {
                    feedbackState(
                        title: "No matches loaded yet",
                        text: "Use Load Fixtures to fetch the \(FootballCompetitionPreset.suggestionWindowDescription) for this competition.",
                        systemImage: "sportscourt",
                        tint: .secondary,
                        buttonTitle: "Load Fixtures"
                    ) {
                        await loadCompetitionFixtures(section)
                    }
                } else if section.matches.isEmpty {
                    emptyState("No matches available in the \(FootballCompetitionPreset.suggestionWindowDescription).")
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
                } else if section.errorMessage != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
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
                    LazyVGrid(columns: matchGridColumns, alignment: .leading, spacing: 12) {
                        ForEach(upcomingManagedMatches) { match in
                            matchCard(
                                match,
                                showsCompetitionName: sharedAddedMatchesCompetitionTitle == nil,
                                showsSeparateMetadataRows: true
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(panelChrome)
    }

    private var liveAndNextDayPanel: some View {
        let section = footballLiveAndNextDaySection

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

            if let sharedLiveAndNextDayCompetitionTitle {
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
                    systemImage: "sportscourt",
                    tint: .secondary,
                    buttonTitle: "Retry"
                ) {
                    await retryLiveAndNextDayLoad()
                }
            } else if section.matches.isEmpty {
                emptyState("No live matches or fixtures in the next 24 hours are available right now.")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(liveAndNextDayMatchesByRegion.enumerated()), id: \.element.region.id) { index, entry in
                        liveMatchesRegionSection(
                            title: entry.region.title,
                            matches: entry.matches,
                            showsCompetitionName: sharedLiveAndNextDayCompetitionTitle == nil
                        )

                        if index < liveAndNextDayMatchesByRegion.count - 1 {
                            Divider()
                                .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(panelChrome)
    }

    private func liveMatchesRegionSection(
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
            competitionLogo(
                localPath: localCompetitionLogoPath(for: match),
                remoteURL: match.competitionLogoURL
            )
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
            competitionLogo(
                localPath: localCompetitionLogoPath(for: match),
                remoteURL: match.competitionLogoURL
            )
            Text(match.competitionName)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func sharedCompetitionHeader(text: String, localLogoPath: String?, remoteLogoURL: URL?) -> some View {
        HStack(spacing: 6) {
            competitionLogo(localPath: localLogoPath, remoteURL: remoteLogoURL)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private func matchCardActions(_ match: FootballFixtureMatch) -> some View {
        if managedFootballMatchIDs.contains(match.id) {
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
                teamLogo(
                    localPath: localTeamLogoPath(for: team),
                    remoteURL: FootballFixtureFormatter.isUnknownTeam(team) ? nil : team.logoURL
                )
                Text(FootballFixtureFormatter.teamDisplayIdentifier(for: team))
            } else {
                Text(FootballFixtureFormatter.teamDisplayIdentifier(for: team))
                teamLogo(
                    localPath: localTeamLogoPath(for: team),
                    remoteURL: FootballFixtureFormatter.isUnknownTeam(team) ? nil : team.logoURL
                )
            }
        }
    }

    @ViewBuilder
    private func teamLogo(localPath: String?, remoteURL: URL?) -> some View {
        if let localPath,
           let image = NSImage(contentsOfFile: localPath) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 18, height: 18)
        } else {
            AsyncImage(url: remoteURL, transaction: Transaction(animation: nil)) { phase in
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
    }

    @ViewBuilder
    private func competitionLogo(localPath: String?, remoteURL: URL?) -> some View {
        if let localPath,
           let image = NSImage(contentsOfFile: localPath) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 14, height: 14)
        } else {
            AsyncImage(url: remoteURL, transaction: Transaction(animation: nil)) { phase in
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
    }

    private func localTeamLogoPath(for team: FootballTeamSummary) -> String? {
        guard !FootballFixtureFormatter.isUnknownTeam(team) else { return nil }
        return monitor.footballLocalLogoPathsByTeamID[team.id]
    }

    private func localCompetitionLogoPath(for match: FootballFixtureMatch) -> String? {
        monitor.footballLocalLogoPathsByCompetitionSlug[match.competitionSlug]
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

    @ViewBuilder
    private func feedbackState(
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

    private var shouldRefreshManagedMatchesOnVisibleTick: Bool {
        !managedFootballMatchIDs.isEmpty || !managedFootballMatches.isEmpty
    }

    private func synchronizeViewStateFromMonitor() {
        hasEventsAccess = monitor.hasEventsAccess
        availableEventCalendars = monitor.availableEventCalendars
        footballMenuSections = monitor.footballMenuSections
        footballLiveAndNextDaySection = monitor.footballLiveAndNextDaySection
        managedFootballMatchIDs = monitor.managedFootballMatchIDs
        managedFootballMatches = monitor.managedFootballMatches
        refreshWritableCalendars()
    }

    private func refreshWritableCalendars() {
        writableEventCalendars = hasEventsAccess ? monitor.writableFootballTargetCalendars() : []
    }

    private func loadCompetitionFixtures(_ section: FootballMenuCompetitionSection) async {
        expandedCompetitionIDs.insert(section.id)
        await monitor.loadFootballCompetitionSection(section.competition, force: true)
    }

    private func retryFailedCompetitionLoads() async {
        let sectionsToRetry = competitionSectionsWithErrors.isEmpty
            ? footballMenuSections.filter { expandedCompetitionIDs.contains($0.id) }
            : competitionSectionsWithErrors
        for section in sectionsToRetry {
            await loadCompetitionFixtures(section)
        }
    }

    private func retryLiveAndNextDayLoad() async {
        await monitor.loadFootballLiveAndNextDaySection(force: true)
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
                if shouldRefreshManagedMatchesOnVisibleTick {
                    monitor.refreshManagedFootballTrackingSnapshot(now: refreshedNow)
                }
            }

            if browseMode == .liveAndNextDay {
                await monitor.loadFootballLiveAndNextDaySection(force: true)
            }
            if shouldRefreshManagedMatchesOnVisibleTick {
                await refreshManagedMatchesPanel(now: refreshedNow)
            }
        }
    }

    @MainActor
    private func refreshManagedMatchesPanel(now: Date, force: Bool = false) async {
        guard force || shouldRefreshManagedMatchesOnVisibleTick else { return }
        isRefreshingManagedMatches = true
        defer { isRefreshingManagedMatches = false }
        await monitor.syncManagedFootballEventsIfNeeded(now: now, force: force)
    }
}
