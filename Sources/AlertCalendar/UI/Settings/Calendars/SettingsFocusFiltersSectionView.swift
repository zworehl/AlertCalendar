import SwiftUI

struct SettingsFocusFiltersSectionView: View {
    let monitor: CalendarMonitor
    let eventCalendars: [AvailableCalendar]
    let reminderCalendars: [AvailableCalendar]
    @State private var activeState: FocusCalendarFilterState?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.text("Focus Filters"), systemImage: "moon.circle")
                .font(.headline)
            Text(L10n.text("Choose which calendars and reminder lists appear during each Focus in macOS System Settings. When the Focus ends, your usual selection returns."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.text("System Settings → Focus → Choose a Focus → Add Filter → AlertCalendar"))
                .font(.callout.weight(.medium))
                .textSelection(.enabled)

            if let activeState, activeState.hasActiveOverrides {
                Label(L10n.text("Filtered by Focus"), systemImage: "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(Color.accentColor)
                if let selection = activeState.selection(for: .event) {
                    Text(summary(selection, calendars: eventCalendars, noun: L10n.text("event calendars")))
                }
                if let selection = activeState.selection(for: .reminder) {
                    Text(summary(selection, calendars: reminderCalendars, noun: L10n.text("reminder lists")))
                }
            } else {
                Text(L10n.text("Using your usual calendar selection"))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(L10n.text("Open Focus Settings")) {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") else { return }
                    AlertCalendarWorkspace.open(url)
                }
                Button(L10n.text("Refresh Focus")) {
                    monitor.scheduleFocusFilterRefresh()
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsPanelSurface()
        .onReceive(monitor.$activeFocusCalendarFilterState.removeDuplicates()) { activeState = $0 }
    }

    private func summary(_ selection: FocusCalendarSelectionOverride, calendars: [AvailableCalendar], noun: String) -> String {
        let names = calendars.filter { selection.calendarIDs.contains($0.id) }.map(\.title).sorted()
        guard !names.isEmpty else {
            return selection.action == .showOnlySelected ? L10n.text("No \(noun) visible") : L10n.text("No available \(noun) hidden")
        }
        let list = names.joined(separator: ", ")
        return selection.action == .showOnlySelected ? L10n.text("Show only: \(list)") : L10n.text("Hide: \(list)")
    }
}
