import SwiftUI

@MainActor
struct SettingsEsportsSectionView: View {
    @ObservedObject var runtime: EsportsRuntime
    @Binding var preferences: EsportsSettings
    @Binding var pendingCalendarChanges: [String: SettingsPendingItemChange<EsportsMatch>]
    let calendars: [AvailableCalendar]
    let hasEventsAccess: Bool
    var runsLiveServices = true

    @State var selectedGame: EsportsGame?
    @State var selectedCompetitionKey: String?
    @State var browseMode: SettingsEsportsBrowseMode = .schedule
    @State var visibleNow = AlertCalendarClock.nowRoundedToSecond()
    @State var token = ""
    @State var isConnecting = false
    @State var connectionTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            calendarControls
            providerControls
            browseControls
            refreshStatus
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    localSection
                    providerSection
                }
                .padding(.trailing, 2)
            }
            .frame(minHeight: 180, maxHeight: .infinity)
            .accessibilityIdentifier("settings.esports.matches")
            .transaction { $0.animation = nil }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("settings.esports.content")
        .onChange(of: selectedGame) { _ in selectedCompetitionKey = nil }
        .onChange(of: competitionOptions) { competitions in
            if let selectedCompetitionKey, !competitions.contains(where: { $0.id == selectedCompetitionKey }) {
                self.selectedCompetitionKey = nil
            }
        }
        .task {
            guard runsLiveServices else { return }
            await runtime.refresh(force: false)
        }
        .task {
            guard runsLiveServices else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
                visibleNow = AlertCalendarClock.nowRoundedToSecond()
            }
        }
        .onDisappear {
            token = ""
            connectionTask?.cancel()
            connectionTask = nil
        }
    }

    var writableCalendars: [AvailableCalendar] {
        calendars.filter { $0.kind == .event && $0.allowsContentModifications && !$0.isSubscribed }
    }

    var hasWritableDraftTarget: Bool {
        hasEventsAccess && writableCalendars.contains { $0.id == preferences.targetCalendarID }
    }

    var competitionOptions: [SettingsEsportsCompetition] {
        SettingsEsportsPresentation.competitions(in: runtime.providerMatches, game: selectedGame)
    }

    var displayedProviderMatches: [EsportsMatch] {
        SettingsEsportsPresentation.visibleMatches(
            runtime.providerMatches, game: selectedGame, competitionKey: selectedCompetitionKey,
            mode: browseMode, preferences: preferences, now: visibleNow,
            managedIDs: runtime.managedMatchIDs, pending: pendingCalendarChanges
        )
    }

    var displayedLocalEvents: [LocalGamingCalendarEvent] {
        SettingsEsportsPresentation.visibleLocalEvents(
            runtime.localEvents, game: selectedGame, mode: browseMode, preferences: preferences, now: visibleNow
        )
    }

    var refreshStatus: some View {
        HStack(alignment: .top, spacing: 8) {
            ProgressView().controlSize(.small).opacity(runtime.isRefreshing ? 1 : 0)
                .accessibilityHidden(!runtime.isRefreshing)
            VStack(alignment: .leading, spacing: 3) {
                if let error = runtime.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).lineLimit(2)
                } else if runtime.isRefreshing {
                    Text(L10n.text("Refreshing esports…"))
                } else if let verified = runtime.lastValidatedAt {
                    HStack(spacing: 4) {
                        Text(L10n.text("Last verified"))
                        Text(verified, style: .time)
                    }
                } else {
                    Text(L10n.text("Apple Calendar matches remain available without a provider connection."))
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await runtime.refresh(force: true) }
            } label: { Label(L10n.text("Refresh Now"), systemImage: "arrow.clockwise") }
                .disabled(!runsLiveServices || runtime.isRefreshing)
                .accessibilityIdentifier("settings.esports.refresh")
        }
        .frame(height: 38, alignment: .top)
        .accessibilityIdentifier("settings.esports.status")
    }

    var localSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L10n.text("Apple Calendar"), count: displayedLocalEvents.count, symbol: "calendar")
            Text(L10n.text("Open existing events in Apple Calendar to edit them."))
                .font(.caption).foregroundStyle(.secondary)
            if displayedLocalEvents.isEmpty {
                feedback(hasEventsAccess ? L10n.text("No calendar matches in this view.")
                         : L10n.text("Grant Calendar access to view local esports events."))
            } else {
                LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 10) {
                    ForEach(displayedLocalEvents) { event in
                        SettingsEsportsLocalCard(event: event) { runtime.openLocalEvent(event) }
                    }
                }
            }
        }
    }

    var providerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("PandaScore", count: displayedProviderMatches.count, symbol: "trophy")
            if let game = selectedGame, game.providerSlug == nil {
                feedback(L10n.text("Provider coverage is unavailable for this game. Its Apple Calendar matches remain available."))
            } else if !runtime.isConnected && displayedProviderMatches.isEmpty {
                feedback(L10n.text("Connect PandaScore to browse supported schedules and results."))
            } else if displayedProviderMatches.isEmpty {
                feedback(runtime.isRefreshing ? L10n.text("Loading esports matches…") : L10n.text("No provider matches in this view."))
            } else {
                LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 10) {
                    ForEach(displayedProviderMatches) { match in
                        SettingsEsportsProviderCard(
                            match: match, presence: runtime.presence(of: match), pending: pendingCalendarChanges[match.id],
                            canAdd: hasWritableDraftTarget && runtime.canAddMatch(match),
                            canRemove: hasEventsAccess,
                            toggle: { stageToggle(match) }, open: { runtime.openMatch(match) }
                        )
                    }
                }
            }
        }
    }

    var cardColumns: [GridItem] { [GridItem(.adaptive(minimum: 260, maximum: 440), spacing: 10, alignment: .top)] }

    func sectionHeader(_ title: String, count: Int, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol).font(SettingsTypography.panelTitle)
            Spacer()
            Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    func feedback(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .settingsInsetSurface()
    }

    func stageToggle(_ match: EsportsMatch) {
        pendingCalendarChanges = SettingsEsportsPresentation.toggledPendingChanges(
            for: match, presence: runtime.presence(of: match), changes: pendingCalendarChanges
        )
    }
}
