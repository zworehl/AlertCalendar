import AppKit
import Combine
import SwiftUI

struct SettingsFootballFixturesSectionView: View {
    private enum FootballBrowseMode: String, CaseIterable, Identifiable {
        case competitions = "Competitions"
        case liveAndNextDay = "Now + Next 24h"
        case addedMatches = "Added Matches"

        var id: String { rawValue }
    }

    private static let scrollableMatchCardThreshold = 12
    private static let preferredMatchCardWidth: CGFloat = 306
    private static let minimumMatchCardWidth: CGFloat = 272
    private static let inlineFieldLabelWidth: CGFloat = 96
    private static let topMenuControlWidth: CGFloat = 320
    private static let topShowControlWidth: CGFloat = 500
    private static let matchActionButtonSize: CGFloat = 18
    private static let matchActionSlotWidth: CGFloat = 112

    let monitor: CalendarMonitor

    @AppStorage(DefaultsKeys.footballTargetCalendarID) private var footballTargetCalendarID = ""
    @AppStorage(DefaultsKeys.footballCalendarAlertOption) private var footballCalendarAlertOptionRaw = FootballCalendarAlertOption.none.rawValue
    @AppStorage(DefaultsKeys.showFinishedFootballMatches) private var showFinishedFootballMatches = true
    @State private var browseMode: FootballBrowseMode = .competitions
    @State private var hoveredMatchID: String?
    @State private var selectedCompetitionRegionID: String?
    @State private var selectedCompetitionID: String?
    @State private var isRefreshingManagedMatches = false
    @State private var visibleNow = Date()
    @State private var hasEventsAccess = false
    @State private var availableEventCalendars: [AvailableCalendar] = []
    @State private var writableEventCalendars: [AvailableCalendar] = []
    @State private var footballMenuSections: [FootballMenuCompetitionSection] = []
    @State private var footballLiveAndNextDaySection = FootballMatchesOverviewSection.placeholder(title: "Now & Next 24 Hours")
    @State private var managedFootballMatchIDs: Set<String> = []
    @State private var managedFootballMatches: [FootballFixtureMatch] = []
    @State private var competitionSectionsByRegionCache: [(region: FootballCompetitionRegion, sections: [FootballMenuCompetitionSection])] = []
    @State private var competitionSectionsWithErrorsCache: [FootballMenuCompetitionSection] = []
    @State private var hasAnyCompetitionCardsCache = false
    @State private var hasAttemptedCompetitionLoadsCache = false
    @State private var liveAndNextDayMatchesByRegionCache: [(region: FootballCompetitionRegion, matches: [FootballFixtureMatch])] = []
    @State private var upcomingManagedMatchesCache: [FootballFixtureMatch] = []

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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            switch browseMode {
            case .competitions:
                await loadSelectedCompetitionIfNeeded()
            case .liveAndNextDay:
                await monitor.loadFootballLiveAndNextDaySection(force: false)
            case .addedMatches:
                return
            }
        }
        .task(id: selectedCompetitionID) {
            guard browseMode == .competitions else { return }
            await loadSelectedCompetitionIfNeeded()
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
            refreshManagedMatchesDerivedState(now: now)
            Task {
                if browseMode == .liveAndNextDay {
                    await monitor.loadFootballLiveAndNextDaySection(force: false)
                }
                if shouldRefreshManagedMatchesOnVisibleTick {
                    await refreshManagedMatchesPanel(now: now)
                }
            }
        }
        .onChange(of: footballCalendarAlertOptionRaw) { _ in
            applyFootballCalendarAlertPreference()
        }
        .onChange(of: showFinishedFootballMatches) { _ in
            refreshCompetitionSectionsDerivedState()
            refreshLiveAndNextDayDerivedState()
        }
        .onReceive(monitor.$hasEventsAccess.removeDuplicates()) { value in
            guard hasEventsAccess != value else { return }
            hasEventsAccess = value
            refreshWritableCalendars()
        }
        .onReceive(monitor.$availableEventCalendars.removeDuplicates()) { calendars in
            guard availableEventCalendars != calendars else { return }
            availableEventCalendars = calendars
            refreshWritableCalendars()
        }
        .onReceive(monitor.$footballMenuSections.removeDuplicates()) { sections in
            guard footballMenuSections != sections else { return }
            footballMenuSections = sections
            refreshCompetitionSectionsDerivedState()
        }
        .onReceive(monitor.$footballLiveAndNextDaySection.removeDuplicates()) { section in
            guard footballLiveAndNextDaySection != section else { return }
            footballLiveAndNextDaySection = section
            refreshLiveAndNextDayDerivedState()
        }
        .onReceive(monitor.$managedFootballMatchIDs.removeDuplicates()) { ids in
            guard managedFootballMatchIDs != ids else { return }
            managedFootballMatchIDs = ids
        }
        .onReceive(monitor.$managedFootballMatches.removeDuplicates()) { matches in
            guard managedFootballMatches != matches else { return }
            managedFootballMatches = matches
            refreshManagedMatchesDerivedState(now: visibleNow)
        }
    }

    private var footballContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            footballTopControlsSection

            if browseMode == .competitions && footballMenuSections.isEmpty {
                emptyState("No competitions are configured right now.")
            } else {
                activeMatchesPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            case .addedMatches:
                addedMatchesPanel
            }
        }
    }

    private var upcomingManagedMatches: [FootballFixtureMatch] {
        upcomingManagedMatchesCache
    }

    private var upcomingManagedEventCount: Int {
        upcomingManagedMatches.count
    }

    private var hasUpcomingAddedMatches: Bool {
        upcomingManagedEventCount > 0
    }

    private var isLoadingUpcomingAddedMatches: Bool {
        isRefreshingManagedMatches && !managedFootballMatchIDs.isEmpty && upcomingManagedMatches.isEmpty
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
        FootballFixtureFormatter.sharedCompetitionTitle(for: displayedLiveAndNextDayMatches)
    }

    private var sharedLiveAndNextDayCompetitionLogoURL: URL? {
        guard sharedLiveAndNextDayCompetitionTitle != nil else { return nil }
        return displayedLiveAndNextDayMatches.first?.competitionLogoURL
    }

    private var sharedLiveAndNextDayCompetitionLocalLogoPath: String? {
        guard let match = displayedLiveAndNextDayMatches.first,
              sharedLiveAndNextDayCompetitionTitle != nil else { return nil }
        return localCompetitionLogoPath(for: match)
    }

    private var competitionSectionsByRegion: [(region: FootballCompetitionRegion, sections: [FootballMenuCompetitionSection])] {
        competitionSectionsByRegionCache
    }

    private var selectedCompetitionRegionEntry: (region: FootballCompetitionRegion, sections: [FootballMenuCompetitionSection])? {
        if let selectedCompetitionRegionID,
           let matchingEntry = competitionSectionsByRegion.first(where: { $0.region.id == selectedCompetitionRegionID }) {
            return matchingEntry
        }
        return competitionSectionsByRegion.first
    }

    private var selectedCompetitionSections: [FootballMenuCompetitionSection] {
        selectedCompetitionRegionEntry?.sections ?? []
    }

    private var selectedCompetitionSection: FootballMenuCompetitionSection? {
        if let selectedCompetitionID,
           let matchingSection = selectedCompetitionSections.first(where: { $0.id == selectedCompetitionID }) {
            return matchingSection
        }
        return selectedCompetitionSections.first
    }

    private var liveAndNextDayMatchesByRegion: [(region: FootballCompetitionRegion, matches: [FootballFixtureMatch])] {
        liveAndNextDayMatchesByRegionCache
    }

    private var displayedLiveAndNextDayMatches: [FootballFixtureMatch] {
        liveAndNextDayMatchesByRegion.flatMap(\.matches)
    }

    private var competitionSectionsWithErrors: [FootballMenuCompetitionSection] {
        competitionSectionsWithErrorsCache
    }

    private var hasAnyCompetitionCards: Bool {
        hasAnyCompetitionCardsCache
    }

    private var hasAttemptedCompetitionLoads: Bool {
        hasAttemptedCompetitionLoadsCache
    }

    private var footballTopControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            footballPrimaryControlsSection
        }
    }

    private var footballPrimaryControlsSection: some View {
        HStack(alignment: .top, spacing: 16) {
            addToControlField
                .frame(maxWidth: Self.topMenuControlWidth, alignment: .leading)

            Spacer(minLength: 0)

            showControlField
                .frame(maxWidth: Self.topShowControlWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var addToControlField: some View {
        footballControlField(
            title: "Add To",
            helpText: "This calendar is used when you add a football fixture from the list below.",
            isInline: true
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
        Picker("Football view", selection: $browseMode) {
            ForEach(FootballBrowseMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var calendarAlertControlField: some View {
        footballControlField(
            title: "Calendar Alert",
            helpText: "Applies the same Apple Calendar alert to every football fixture managed by Alert Calendar, including ones already added.",
            isInline: true
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
        isInline: Bool = false,
        @ViewBuilder control: () -> Control
    ) -> some View {
        Group {
            if isInline {
                HStack(alignment: .center, spacing: 10) {
                    footballControlTitle(title: title, helpText: helpText)
                        .frame(width: Self.inlineFieldLabelWidth, alignment: .leading)

                    control()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    footballControlTitle(title: title, helpText: helpText)
                    control()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footballControlTitle(title: String, helpText: String?) -> some View {
        HStack(spacing: 6) {
            Text(title)
            if let helpText {
                InfoTipButton(text: helpText)
            }
        }
        .font(.subheadline.weight(.medium))
    }

    private var competitionListPanel: some View {
        HStack(alignment: .top, spacing: 16) {
            competitionSelectionContentPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            competitionFiltersPanel
                .frame(width: 280, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var competitionSelectionContentPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let section = selectedCompetitionSection {
                let visibleMatches = displayedMatches(section.matches)

                HStack(spacing: 8) {
                    competitionSelectionHeader(for: section)

                    Spacer()

                    if !visibleMatches.isEmpty {
                        competitionBulkActionButton(for: visibleMatches)
                    }

                    if section.isLoading && !section.hasLoaded && section.matches.isEmpty {
                        ProgressView()
                            .controlSize(.small)
                    } else if section.errorMessage != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else if section.hasLoaded {
                        Text("\(visibleMatches.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Load")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                competitionContent(for: section, visibleMatches: visibleMatches)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                emptyState("Choose a competition from the panel on the right.")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelChrome)
    }

    private func competitionSelectionHeader(for section: FootballMenuCompetitionSection) -> some View {
        let logoSource = competitionHeaderLogoSource(for: section)

        return HStack(alignment: .center, spacing: 10) {
            FootballCompetitionLogoView(
                localPath: logoSource?.localPath,
                remoteURL: logoSource?.remoteURL,
                size: 38,
                placeholderSymbolSize: 18
            )
            .frame(width: 38, height: 38, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(section.competition.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let region = selectedCompetitionRegionEntry?.region {
                    Text(region.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var competitionFiltersPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text("Browse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Toggle("Show finished matches", isOn: $showFinishedFootballMatches)
                    .toggleStyle(.checkbox)
                    .font(.subheadline.weight(.medium))
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Region")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(competitionSectionsByRegion, id: \.region.id) { entry in
                    competitionRegionFilterButton(entry)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Competition")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if selectedCompetitionSections.isEmpty {
                    emptyState("No competitions are available for the selected region.")
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(selectedCompetitionSections) { section in
                                competitionSelectionButton(section)
                            }
                        }
                        .padding(.trailing, 2)
                    }
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelChrome)
    }

    @ViewBuilder
    private func competitionContent(
        for section: FootballMenuCompetitionSection,
        visibleMatches: [FootballFixtureMatch]
    ) -> some View {
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
        } else if !section.hasLoaded && !section.isLoading && section.matches.isEmpty {
            feedbackState(
                title: "No matches loaded yet",
                text: "Use Load Fixtures to fetch the \(FootballCompetitionPreset.suggestionWindowDescription) for this competition.",
                systemImage: FootballFixtureFormatter.footballLocationSymbolName,
                tint: .secondary,
                buttonTitle: "Load Fixtures"
            ) {
                await loadCompetitionFixtures(section)
            }
        } else if visibleMatches.isEmpty {
            emptyState(showFinishedFootballMatches
                ? "No matches available in the \(FootballCompetitionPreset.suggestionWindowDescription)."
                : "No unfinished matches available in the \(FootballCompetitionPreset.suggestionWindowDescription)."
            )
        } else {
            matchCardsViewport(visibleMatches, showsCompetitionName: false)
        }
    }

    private func competitionRegionFilterButton(_ entry: (region: FootballCompetitionRegion, sections: [FootballMenuCompetitionSection])) -> some View {
        let isSelected = entry.region.id == selectedCompetitionRegionEntry?.region.id

        return Button {
            selectedCompetitionRegionID = entry.region.id
            selectedCompetitionID = entry.sections.first?.id
        } label: {
            HStack(spacing: 8) {
                Text(entry.region.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text("\(entry.sections.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.92) : .secondary)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func competitionSelectionButton(_ section: FootballMenuCompetitionSection) -> some View {
        let isSelected = section.id == selectedCompetitionSection?.id
        let visibleMatchCount = displayedMatches(section.matches).count

        return Button {
            selectedCompetitionRegionID = section.competition.region.id
            selectedCompetitionID = section.id
        } label: {
            HStack(spacing: 8) {
                Text(section.competition.title)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if section.isLoading && !section.hasLoaded && section.matches.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                } else if section.errorMessage != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if section.hasLoaded {
                    Text("\(visibleMatchCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? .white.opacity(0.92) : .secondary)
                } else {
                    Text("Load")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? .white.opacity(0.92) : .secondary)
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
                systemImage: FootballFixtureFormatter.footballLocationSymbolName,
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

    private var liveAndNextDayPanel: some View {
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

    private func liveAndNextDayRegionsContent(
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

    private var panelChrome: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func matchCardsViewport(
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

    private func matchCardsGrid(
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
    private func matchCard(
        _ match: FootballFixtureMatch,
        showsCompetitionName: Bool,
        showsSeparateMetadataRows: Bool = false
    ) -> some View {
        let trailingStatusAccessories = FootballStatusAccessoriesView.accessories(for: match, now: visibleNow)
        let inlineAccessories = FootballStatusAccessoriesData(
            badgeText: nil,
            warningText: trailingStatusAccessories.warningText
        )
        let warningText = CalendarMonitor.footballStatusWarningText(for: match)
        let warningSummary = warningText.flatMap { _ in CalendarMonitor.footballStatusWarningSummary(for: match) }
        let isHovered = hoveredMatchID == match.id
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
        .onHover { hovering in
            if hovering {
                hoveredMatchID = match.id
            } else if hoveredMatchID == match.id {
                hoveredMatchID = nil
            }
        }
        .animation(.easeInOut(duration: 0.14), value: isHovered)
    }

    @ViewBuilder
    private func matchCardMetadataRows(_ match: FootballFixtureMatch, showsCompetitionName: Bool) -> some View {
        if let scheduleText = footballCardScheduleText(for: match),
           footballCardTrailingText(for: match) == nil,
           footballCardTrailingBadgeText(for: match) == nil {
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

    private func competitionInlineLabel(_ match: FootballFixtureMatch) -> some View {
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

    private func sharedCompetitionHeader(text: String, localLogoPath: String?, remoteLogoURL: URL?) -> some View {
        HStack(spacing: 6) {
            FootballCompetitionLogoView(localPath: localLogoPath, remoteURL: remoteLogoURL)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private func matchCardTrailingAccessory(_ match: FootballFixtureMatch, isHovered: Bool) -> some View {
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
    private func matchCardActions(_ match: FootballFixtureMatch, isVisible: Bool) -> some View {
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

    private func removeMatchButton(_ match: FootballFixtureMatch, isVisible: Bool) -> some View {
        actionIconButton(
            systemName: "minus",
            tint: .red,
            helpText: "Remove this event from Apple Calendar",
            isVisible: isVisible
        ) {
            monitor.removeFootballMatchFromCalendar(match)
        }
    }

    private func actionIconButton(
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
    private func fixtureTitleRow(_ match: FootballFixtureMatch, accessories: FootballStatusAccessoriesData) -> some View {
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

    private func teamLabelRow(_ team: FootballTeamSummary, logoLeading: Bool) -> some View {
        HStack(spacing: 4) {
            if logoLeading {
                FootballTeamLogoView(
                    localPath: localTeamLogoPath(for: team),
                    remoteURL: team.logoURL,
                    isUnknown: FootballFixtureFormatter.isUnknownTeam(team),
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
                    size: 18,
                    placeholderSymbolSize: 9
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func teamNameText(_ team: FootballTeamSummary) -> some View {
        Text(FootballFixtureFormatter.teamDisplayIdentifier(for: team))
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func localTeamLogoPath(for team: FootballTeamSummary) -> String? {
        guard !FootballFixtureFormatter.isUnknownTeam(team) else { return nil }
        return monitor.footballLocalLogoPathsByTeamID[team.id]
    }

    private func localCompetitionLogoPath(for match: FootballFixtureMatch) -> String? {
        monitor.footballLocalLogoPathsByCompetitionSlug[match.competitionSlug]
    }

    private func competitionHeaderLogoSource(
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

    private func footballCardStatusText(for match: FootballFixtureMatch) -> String? {
        nil
    }

    private func footballCardScheduleText(for match: FootballFixtureMatch) -> String? {
        CalendarMonitor.footballScheduleText(for: match, now: visibleNow)
    }

    private func footballCardTrailingBadgeText(for match: FootballFixtureMatch) -> String? {
        CalendarMonitor.footballStatusBadgeText(for: match, now: visibleNow)
    }

    private func footballCardTrailingText(for match: FootballFixtureMatch) -> String? {
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

    private func competitionBulkActionButton(for matches: [FootballFixtureMatch]) -> some View {
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

    private func applyCompetitionBulkAction(
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

        let now = Self.minuteReferenceDate(for: Date())
        visibleNow = now
        await refreshManagedMatchesPanel(now: now, force: true)
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
        refreshManagedMatchesDerivedState(now: now)
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
        refreshCompetitionSectionsDerivedState()
        refreshLiveAndNextDayDerivedState()
        refreshManagedMatchesDerivedState(now: visibleNow)
        refreshWritableCalendars()
    }

    private func refreshWritableCalendars() {
        let nextCalendars = hasEventsAccess ? monitor.writableFootballTargetCalendars() : []
        guard writableEventCalendars != nextCalendars else { return }
        writableEventCalendars = nextCalendars
    }

    private func loadCompetitionFixtures(_ section: FootballMenuCompetitionSection) async {
        await monitor.loadFootballCompetitionSection(section.competition, force: true)
    }

    private func loadSelectedCompetitionIfNeeded() async {
        guard let section = selectedCompetitionSection else { return }
        await monitor.loadFootballCompetitionSection(section.competition, force: true)
    }

    private func retryFailedCompetitionLoads() async {
        let sectionsToRetry = competitionSectionsWithErrors.isEmpty
            ? (selectedCompetitionSection.map { [$0] } ?? [])
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
                refreshManagedMatchesDerivedState(now: refreshedNow)
            }

            if browseMode == .liveAndNextDay {
                await monitor.loadFootballLiveAndNextDaySection(force: false)
            }
            if shouldRefreshManagedMatchesOnVisibleTick {
                await refreshManagedMatchesPanel(now: refreshedNow)
            }
        }
    }

    @MainActor
    private func refreshManagedMatchesPanel(now: Date, force: Bool = false) async {
        guard !force || shouldRefreshManagedMatchesOnVisibleTick || !monitor.managedFootballEventRecords.isEmpty else {
            return
        }
        guard force || shouldRefreshManagedMatchesOnVisibleTick else { return }
        isRefreshingManagedMatches = true
        defer { isRefreshingManagedMatches = false }
        await monitor.syncManagedFootballEventsIfNeeded(now: now, force: force)
    }

    private func refreshCompetitionSectionsDerivedState() {
        competitionSectionsByRegionCache = FootballCompetitionRegion.allCases.compactMap { region in
            let sections = footballMenuSections.filter { $0.competition.region == region }
            guard !sections.isEmpty else { return nil }
            return (region, sections)
        }
        competitionSectionsWithErrorsCache = footballMenuSections.filter { $0.errorMessage != nil }
        hasAnyCompetitionCardsCache = footballMenuSections.contains { !displayedMatches($0.matches).isEmpty }
        hasAttemptedCompetitionLoadsCache = footballMenuSections.contains {
            $0.hasLoaded || $0.isLoading || $0.errorMessage != nil
        }
        synchronizeCompetitionSelection()
    }

    private func refreshLiveAndNextDayDerivedState() {
        let visibleMatches = displayedMatches(footballLiveAndNextDaySection.matches)
        let nextRegions = FootballCompetitionRegion.allCases.compactMap { region -> (region: FootballCompetitionRegion, matches: [FootballFixtureMatch])? in
            let matches = visibleMatches.filter { $0.competitionRegion == region }
            guard !matches.isEmpty else { return nil }
            guard matches.contains(where: { $0.statusState == .scheduled }) else { return nil }
            return (region, matches)
        }

        liveAndNextDayMatchesByRegionCache = nextRegions
    }

    private func displayedMatches(_ matches: [FootballFixtureMatch]) -> [FootballFixtureMatch] {
        guard !showFinishedFootballMatches else { return matches }
        return matches.filter { $0.statusState != .finished }
    }

    private func refreshManagedMatchesDerivedState(now: Date) {
        let nextMatches = CalendarMonitor.upcomingManagedFootballMatches(
            from: managedFootballMatches,
            now: now
        )
        guard upcomingManagedMatchesCache != nextMatches else { return }
        upcomingManagedMatchesCache = nextMatches
    }

    private func synchronizeCompetitionSelection() {
        guard let regionEntry = selectedCompetitionRegionEntry else {
            selectedCompetitionRegionID = nil
            selectedCompetitionID = nil
            return
        }

        if selectedCompetitionRegionID != regionEntry.region.id {
            selectedCompetitionRegionID = regionEntry.region.id
        }

        let availableCompetitionIDs = Set(regionEntry.sections.map(\.id))
        guard availableCompetitionIDs.contains(selectedCompetitionID ?? "") else {
            selectedCompetitionID = regionEntry.sections.first?.id
            return
        }
    }
}
