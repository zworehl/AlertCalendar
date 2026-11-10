import SwiftUI

extension SettingsEsportsSectionView {
    var calendarControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    destinationControl.frame(maxWidth: SettingsFootballFixturesSectionView.topMenuControlWidth, alignment: .leading)
                    alertControl.frame(maxWidth: SettingsFootballFixturesSectionView.topMenuControlWidth, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 10) { destinationControl; alertControl }
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
            selection: $preferences.alertLeadMinutes,
            layout: .inline(labelWidth: SettingsVisualMetrics.calendarAlertLabelWidth)
        ) {
            ForEach(Array(Set([-1, 0, 5, 10, 15, 30, 60, 1_440, preferences.alertLeadMinutes])).sorted(), id: \.self) { minutes in
                if minutes < 0 { Text(L10n.text("None")).tag(minutes) }
                else if minutes == 0 { Text(L10n.text("At time of event")).tag(minutes) }
                else { Text("\(minutes) min").tag(minutes) }
            }
        }
        .accessibilityIdentifier("settings.esports.alert")
    }

    func windowControl(title: String, value: Binding<Int>, range: ClosedRange<Int>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(value.wrappedValue)").monospacedDigit()
                    Text(value.wrappedValue == 1 ? L10n.text("day") : L10n.text("days"))
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(value.wrappedValue) },
                                  set: { value.wrappedValue = Int($0.rounded()) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                .accessibilityLabel(title)
                .accessibilityIdentifier("settings.esports.\(id)")
        }
    }

    var providerControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Esports Calendar", systemImage: "globe")
                .font(SettingsTypography.panelTitle)
            Text(L10n.text("Public schedule. No account or API token required. Updated every 2 hours."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsLabeledCheckboxGroup(
                title: L10n.text("Public feed games"),
                helpText: L10n.text("Choose which supported games to fetch after Apply.")
            ) {
                ForEach(EsportsCatalog.providerGames) { game in
                    Toggle(game.displayName, isOn: providerGameBinding(game))
                        .accessibilityIdentifier("settings.esports.providerGame.\(game.rawValue)")
                }
            }
            if !preferences.autoAddCompetitionIDs.isEmpty {
                Button { preferences.autoAddCompetitionIDs = [] } label: {
                    Label(L10n.text("Turn off automatic additions"), systemImage: "xmark.circle")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderless).font(.caption)
                .accessibilityIdentifier("settings.esports.disableAutoAdd")
            }
        }
        .settingsPanelSurface(padding: SettingsVisualMetrics.interactiveCardPadding)
        .accessibilityIdentifier("settings.esports.publicSource")
    }

    func providerGameBinding(_ game: EsportsGame) -> Binding<Bool> {
        Binding(get: { preferences.providerGames.contains(game) }, set: { selected in
            if selected { preferences.providerGames.insert(game) }
            else { preferences.providerGames.remove(game) }
        })
    }

    var browseControls: some View {
        Picker(L10n.text("Show"), selection: $browseMode) {
            ForEach(SettingsEsportsBrowseMode.allCases) { mode in
                Image(systemName: mode.symbolName)
                    .accessibilityLabel(Text(mode.title))
                    .help(mode.title)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .trailing)
        .help(browseMode.title)
        .accessibilityIdentifier("settings.esports.mode")
    }

    func autoAddBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { preferences.autoAddCompetitionIDs.contains(key) }, set: { selected in
            if selected { preferences.autoAddCompetitionIDs.insert(key) }
            else { preferences.autoAddCompetitionIDs.remove(key) }
        })
    }
}
