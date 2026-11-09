import SwiftUI

extension SettingsEsportsSectionView {
    var esportsColumns: some View {
        HStack(alignment: .top, spacing: SettingsFootballFixturesSectionView.competitionColumnSpacing) {
            VStack(alignment: .leading, spacing: 12) {
                calendarControls
                SettingsSectionDivider()
                selectionHeader
                refreshStatus
                matchesViewport
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            SettingsVerticalDivider()

            VStack(alignment: .leading, spacing: 12) {
                browseControls
                SettingsSectionDivider()
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        windowControl(title: L10n.text("Past window"), value: $preferences.lookbackDays,
                                      range: 0...365, id: "lookback")
                        windowControl(title: L10n.text("Ahead window"), value: $preferences.lookaheadDays,
                                      range: 1...180, id: "lookahead")
                        SettingsSectionDivider()
                        gameFilters
                        SettingsSectionDivider()
                        competitionFilters
                    }
                    .padding(.trailing, 2)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .clipped()
                SettingsSectionDivider()
                providerControls
            }
            .frame(width: SettingsFootballFixturesSectionView.competitionSidebarWidth, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var matchesViewport: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 14) {
                localSection
                providerSection
            }
            .padding(.trailing, 2)
        }
        .frame(minHeight: SettingsFootballFixturesSectionView.minimumMatchListViewportHeight, maxHeight: .infinity)
        .accessibilityIdentifier("settings.esports.matches")
        .transaction { $0.animation = nil }
    }

    var selectionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(competitionOptions.first { $0.id == selectedCompetitionKey }?.name
                 ?? selectedGame?.displayName ?? L10n.text("All games"))
                .font(SettingsTypography.panelTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let key = selectedCompetitionKey {
                Toggle(L10n.text("Auto-add this competition"), isOn: autoAddBinding(key))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .disabled(!hasWritableDraftTarget)
                    .help(L10n.text("Off by default. New matches from this competition are added only after you apply this choice."))
                    .accessibilityIdentifier("settings.esports.autoAdd")
            }
        }
    }

    var gameFilters: some View {
        let matches = SettingsEsportsPresentation.visibleMatches(
            runtime.providerMatches, game: nil, competitionKey: nil, mode: browseMode,
            preferences: preferences, now: visibleNow, managedIDs: runtime.managedMatchIDs, pending: pendingCalendarChanges
        )
        let events = SettingsEsportsPresentation.visibleLocalEvents(
            runtime.localEvents, game: nil, mode: browseMode, preferences: preferences, now: visibleNow
        )
        let counts = Dictionary(grouping: matches, by: \.game).mapValues(\.count)
            .merging(Dictionary(grouping: events, by: \.game).mapValues(\.count), uniquingKeysWith: +)
        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("Game")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            selectionRow(title: L10n.text("All games"), count: matches.count + events.count,
                         isSelected: selectedGame == nil, id: "game.all") { selectedGame = nil }
            ForEach(EsportsGame.allCases) { game in
                selectionRow(title: game.displayName, count: counts[game] ?? 0,
                             isSelected: selectedGame == game, id: "game.\(game.rawValue)") { selectedGame = game }
            }
        }
    }

    var competitionFilters: some View {
        let matches = SettingsEsportsPresentation.visibleMatches(
            runtime.providerMatches, game: selectedGame, competitionKey: nil, mode: browseMode,
            preferences: preferences, now: visibleNow, managedIDs: runtime.managedMatchIDs, pending: pendingCalendarChanges
        )
        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("Competition")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .help(L10n.text("Competition filters apply to PandaScore matches. Calendar events keep their original titles."))
            selectionRow(title: L10n.text("All competitions"), count: matches.count,
                         isSelected: selectedCompetitionKey == nil, id: "competition.all") { selectedCompetitionKey = nil }
            ForEach(competitionOptions) { competition in
                let count = matches.filter { match in
                    match.competitionID.map { "\(match.game.rawValue):\($0)" } == competition.id
                }.count
                selectionRow(title: selectedGame == nil ? "\(competition.name) · \(competition.game.displayName)" : competition.name,
                             count: count, isSelected: selectedCompetitionKey == competition.id,
                             id: "competition.\(competition.id)") { selectedCompetitionKey = competition.id }
            }
            if competitionOptions.isEmpty {
                Text(L10n.text("Competition unavailable")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    func selectionRow(title: String, count: Int, isSelected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).lineLimit(2).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(count)").font(.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(isSelected ? Color(nsColor: .selectedControlTextColor).opacity(0.92) : .secondary)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color(nsColor: .selectedControlTextColor) : .primary)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(SettingsSelectionRowChrome(isSelected: isSelected))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("settings.esports.\(id)")
    }
}
