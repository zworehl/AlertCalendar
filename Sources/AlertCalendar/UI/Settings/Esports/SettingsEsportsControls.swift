import SwiftUI

extension SettingsEsportsSectionView {
    var calendarControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) {
                    destinationControl.frame(minWidth: 280)
                    alertControl.frame(minWidth: 220)
                }
                VStack(alignment: .leading, spacing: 10) { destinationControl; alertControl }
            }
            HStack(spacing: 18) {
                windowControl(title: L10n.text("Past window"), value: $preferences.lookbackDays,
                              range: 0...365, id: "lookback")
                windowControl(title: L10n.text("Ahead window"), value: $preferences.lookaheadDays,
                              range: 1...180, id: "lookahead")
            }
            if !hasEventsAccess {
                Label(L10n.text("Calendar access is required to add matches."), systemImage: "lock")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var destinationControl: some View {
        SettingsAddToCalendarPicker(
            selection: $preferences.targetCalendarID, calendars: writableCalendars,
            pickerTitle: L10n.text("Add esports matches to calendar"),
            helpText: L10n.text("Only matches explicitly added here or enabled for automatic addition are written to this calendar."),
            emptySelectionTitle: L10n.text("Choose a calendar")
        )
        .disabled(!hasEventsAccess || writableCalendars.isEmpty)
        .accessibilityIdentifier("settings.esports.calendar")
    }

    var alertControl: some View {
        SettingsLabeledMenuPicker(
            title: L10n.text("Calendar Alert"), pickerTitle: L10n.text("Esports event alert"),
            selection: $preferences.alertLeadMinutes
        ) {
            ForEach(Array(Set([0, 5, 10, 15, 30, 60, 1_440, preferences.alertLeadMinutes])).sorted(), id: \.self) { minutes in
                if minutes == 0 { Text(L10n.text("At time of event")).tag(minutes) }
                else { Text("\(minutes) min").tag(minutes) }
            }
        }
        .accessibilityIdentifier("settings.esports.alert")
    }

    func windowControl(title: String, value: Binding<Int>, range: ClosedRange<Int>, id: String) -> some View {
        Stepper(value: value, in: range) {
            HStack(spacing: 5) {
                Text(title)
                Text("\(value.wrappedValue)").monospacedDigit()
                Text(L10n.text("days"))
            }
            .font(.caption)
        }
        .accessibilityIdentifier("settings.esports.\(id)")
    }

    var providerControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("PandaScore").font(SettingsTypography.panelTitle)
                        Text(runtime.isConnected ? L10n.text("Connected") : L10n.text("Optional connection"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(L10n.text("Schedules, match status and final results."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if runtime.isConnected {
                    Button(L10n.text("Disconnect")) {
                        token = ""
                        connectionTask?.cancel()
                        connectionTask = Task { await runtime.disconnect() }
                    }
                    .disabled(!runsLiveServices || isConnecting)
                    .accessibilityIdentifier("settings.esports.disconnect")
                } else {
                    SecureField(L10n.text("PandaScore API token"), text: $token)
                        .textFieldStyle(.roundedBorder).frame(minWidth: 150, maxWidth: 240)
                        .disabled(isConnecting || !runsLiveServices)
                        .accessibilityIdentifier("settings.esports.token")
                        .onSubmit { connectProvider() }
                    Button(isConnecting ? L10n.text("Connecting…") : L10n.text("Connect")) { connectProvider() }
                        .disabled(!runsLiveServices || isConnecting || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("settings.esports.connect")
                }
            }
            SettingsLabeledCheckboxGroup(
                title: L10n.text("Provider games"),
                helpText: L10n.text("Choose which supported games to fetch after Apply. Calendar matches remain available for all seven games.")
            ) {
                ForEach(EsportsGame.allCases.filter { $0.providerSlug != nil }) { game in
                    Toggle(game.displayName, isOn: providerGameBinding(game))
                        .accessibilityIdentifier("settings.esports.providerGame.\(game.rawValue)")
                }
            }
            if !preferences.autoAddCompetitionIDs.isEmpty {
                Button(L10n.text("Turn off automatic additions")) {
                    preferences.autoAddCompetitionIDs = []
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .accessibilityIdentifier("settings.esports.disableAutoAdd")
            }
        }
        .settingsPanelSurface()
    }

    func providerGameBinding(_ game: EsportsGame) -> Binding<Bool> {
        Binding(get: { preferences.providerGames.contains(game) }, set: { selected in
            if selected { preferences.providerGames.insert(game) }
            else { preferences.providerGames.remove(game) }
        })
    }

    func connectProvider() {
        guard runsLiveServices, !isConnecting else { return }
        let credential = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credential.isEmpty else { return }
        token = ""
        isConnecting = true
        connectionTask?.cancel()
        connectionTask = Task {
            await runtime.connect(token: credential)
            isConnecting = false
        }
    }

    var browseControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                SettingsLabeledMenuPicker(title: L10n.text("Game"), pickerTitle: L10n.text("Esports game"), selection: $selectedGame) {
                    Text(L10n.text("All games")).tag(EsportsGame?.none)
                    ForEach(EsportsGame.allCases) { game in Text(game.displayName).tag(Optional(game)) }
                }
                .accessibilityIdentifier("settings.esports.game")
                SettingsLabeledMenuPicker(
                    title: L10n.text("Competition"), pickerTitle: L10n.text("Esports competition"),
                    selection: $selectedCompetitionKey,
                    helpText: L10n.text("Competition filters apply to PandaScore matches. Calendar events keep their original titles.")
                ) {
                    Text(L10n.text("All competitions")).tag(String?.none)
                    ForEach(competitionOptions) { competition in
                        Text(selectedGame == nil ? "\(competition.name) · \(competition.game.displayName)" : competition.name)
                            .tag(Optional(competition.id))
                    }
                }
                .accessibilityIdentifier("settings.esports.competition")
            }
            HStack(spacing: 16) {
                Picker(L10n.text("Show"), selection: $browseMode) {
                    ForEach(SettingsEsportsBrowseMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.esports.mode")
                if let key = selectedCompetitionKey {
                    Toggle(L10n.text("Auto-add this competition"), isOn: autoAddBinding(key))
                        .disabled(!hasWritableDraftTarget)
                        .help(L10n.text("Off by default. New matches from this competition are added only after you apply this choice."))
                        .accessibilityIdentifier("settings.esports.autoAdd")
                }
            }
        }
    }

    func autoAddBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { preferences.autoAddCompetitionIDs.contains(key) }, set: { selected in
            if selected { preferences.autoAddCompetitionIDs.insert(key) }
            else { preferences.autoAddCompetitionIDs.remove(key) }
        })
    }
}
