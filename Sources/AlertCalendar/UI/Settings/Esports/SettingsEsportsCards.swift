import SwiftUI

struct SettingsEsportsLocalCard: View {
    let event: LocalGamingCalendarEvent
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center) {
                Label(L10n.text("Source: Apple Calendar"), systemImage: "calendar")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                SettingsCalendarCardActionButton(calendarAction: .open, action: open)
                    .accessibilityIdentifier("settings.esports.local.\(event.id).open")
            }
            Text(event.title).font(SettingsTypography.itemTitle).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
            Text(event.game.displayName).font(.caption.weight(.semibold))
            HStack(spacing: 5) {
                Text(event.startDate, style: .date)
                if !event.isAllDay { Text(event.startDate, style: .time) }
                else { Text(L10n.text("All day")) }
            }
            .font(.caption).foregroundStyle(.secondary)
            Text(event.calendarName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(L10n.text("Read-only calendar event"))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .settingsInsetSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.esports.local.\(event.id)")
    }
}

struct SettingsEsportsProviderCard: View {
    let match: EsportsMatch
    let presence: EsportsMatchPresence
    let pending: SettingsPendingItemChange<EsportsMatch>?
    let canAdd: Bool
    let canRemove: Bool
    let toggle: () -> Void
    let open: () -> Void

    private var effectivePresent: Bool { pending?.mutation.makesItemPresent ?? (presence != .absent) }
    private var isManaged: Bool { presence == .managed || pending?.mutation == .add }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 6) {
                Label(L10n.text("Source: PandaScore"), systemImage: "trophy")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                actions
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(match.game.displayName).font(.caption.weight(.semibold))
                Spacer(minLength: 2)
                Text(SettingsEsportsPresentation.statusText(match.status))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(match.name).font(SettingsTypography.itemTitle).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
            opponentRows.frame(minHeight: 38, alignment: .top)
            Text(match.competitionName.isEmpty ? L10n.text("Competition unavailable") : match.competitionName)
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .frame(minHeight: 28, alignment: .topLeading)
            matchTime
            HStack(spacing: 6) {
                if match.rescheduled { Text(L10n.text("Rescheduled")) }
                if match.forfeit { Text(L10n.text("Forfeit")) }
                if let games = match.numberOfGames, games > 0 { Text("BO\(games)") }
                Spacer(minLength: 0)
                if let stream = EsportsStreamURLPolicy.safeURL(match.streamURL) {
                    Link(destination: stream) { Label(L10n.text("Stream"), systemImage: "play.rectangle") }
                        .labelStyle(.iconOnly)
                        .frame(width: SettingsVisualMetrics.minimumInteractiveControlSize,
                               height: SettingsVisualMetrics.minimumInteractiveControlSize)
                        .contentShape(Rectangle())
                        .help(L10n.text("Stream"))
                        .accessibilityLabel(L10n.text("Stream"))
                        .accessibilityIdentifier("settings.esports.provider.\(match.id).stream")
                }
            }
            .font(.caption).foregroundStyle(.secondary).frame(height: SettingsVisualMetrics.minimumInteractiveControlSize)
            managementLabel.frame(height: 16, alignment: .leading)
        }
        .settingsInsetSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.esports.provider.\(match.id)")
    }

    @ViewBuilder
    private var actions: some View {
        if presence != .absent {
            SettingsCalendarCardActionButton(calendarAction: .open, action: open)
                .accessibilityIdentifier("settings.esports.provider.\(match.id).open")
        }
        if presence == .absent || presence == .managed {
            SettingsCalendarCardActionButton(calendarAction: effectivePresent ? .remove : .add, action: toggle)
                .disabled(!SettingsEsportsPresentation.canTogglePendingChange(
                    presence: presence, pending: pending, canAdd: canAdd, canRemove: canRemove
                ))
                .accessibilityIdentifier("settings.esports.provider.\(match.id).toggle")
        } else if pending != nil {
            Button(action: toggle) { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.bordered)
                .accessibilityLabel(L10n.text("Undo pending change"))
                .help(L10n.text("Undo pending change"))
                .accessibilityIdentifier("settings.esports.provider.\(match.id).undo")
        }
    }

    @ViewBuilder
    private var opponentRows: some View {
        if match.opponents.isEmpty {
            Text(L10n.text("Participants unavailable")).font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 3) {
                ForEach(match.opponents.map(OpponentRow.init)) { row in
                    let opponent = row.opponent
                    HStack(spacing: 8) {
                        Text(opponent.name).font(.caption).lineLimit(1)
                        Spacer(minLength: 4)
                        if match.status == .running || match.status == .finished {
                            let score = SettingsEsportsPresentation.displayedScore(for: opponent, in: match)
                            Text(score.map(String.init) ?? "—")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .frame(width: 30, alignment: .trailing)
                                .accessibilityLabel(score.map(String.init) ?? L10n.text("Score unavailable"))
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private var matchTime: some View {
        if let date = SettingsEsportsPresentation.startDate(for: match) {
            HStack(spacing: 5) {
                Image(systemName: "clock").accessibilityHidden(true)
                Text(date, style: .date)
                Text(date, style: .time)
            }
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        } else {
            Text(L10n.text("Time not confirmed")).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var managementLabel: some View {
        if let pending {
            Text(pending.mutation == .add ? L10n.text("Pending addition") : L10n.text("Pending removal"))
                .font(.caption2).foregroundStyle(.orange)
        } else if isManaged {
            Text(L10n.text("Managed by AlertCalendar")).font(.caption2).foregroundStyle(.secondary)
        } else if presence != .absent {
            Text(L10n.text("Calendar event found")).font(.caption2).foregroundStyle(.secondary)
        } else {
            Text(L10n.text("Not added")).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private struct OpponentRow: Identifiable {
        let opponent: EsportsOpponent
        var id: String { "\(opponent.type.rawValue):\(opponent.id)" }
    }
}
