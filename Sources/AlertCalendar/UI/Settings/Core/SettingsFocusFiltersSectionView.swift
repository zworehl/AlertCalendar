import SwiftUI

struct SettingsFocusFiltersSectionView: View {
    let activeState: FocusCalendarFilterState?
    let availableEventCalendars: [AvailableCalendar]
    let availableReminderCalendars: [AvailableCalendar]
    let onSyncNow: () -> Void
    let onOpenSystemSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configure per-Focus calendar visibility in macOS System Settings. Alert Calendar keeps the Default Selection above as the base layer, then applies the active Focus override on top.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("System Settings > Focus > Choose a Focus > Add Filter > Alert Calendar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 8) {
                statusRow(
                    title: "Current Focus Override",
                    value: activeState?.hasActiveOverrides == true ? "Active" : "Using default calendar selection"
                )
                statusRow(
                    title: "Event Calendars",
                    value: summaryText(
                        for: activeState?.selection(for: .event),
                        calendars: availableEventCalendars
                    )
                )
                statusRow(
                    title: "Reminder Lists",
                    value: summaryText(
                        for: activeState?.selection(for: .reminder),
                        calendars: availableReminderCalendars
                    )
                )
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    syncButton
                    systemSettingsButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    syncButton
                    systemSettingsButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var syncButton: some View {
        Button(action: onSyncNow) {
            Label("Sync Active Focus", systemImage: "arrow.clockwise")
        }
    }

    private var systemSettingsButton: some View {
        Button(action: onOpenSystemSettings) {
            Label("Open System Settings", systemImage: "gearshape")
        }
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(title):")
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func summaryText(
        for selection: FocusCalendarSelectionOverride?,
        calendars: [AvailableCalendar]
    ) -> String {
        guard let selection, selection.isActive else {
            return "Use default selection"
        }

        let names = calendars
            .filter { selection.calendarIDs.contains($0.id) }
            .map(\.title)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        guard !names.isEmpty else {
            return "Use default selection"
        }

        let visibleNames: String
        if names.count > 3 {
            visibleNames = names.prefix(3).joined(separator: ", ") + " +\(names.count - 3) more"
        } else {
            visibleNames = names.joined(separator: ", ")
        }

        switch selection.action {
        case .hideSelected:
            return "Hide \(visibleNames)"
        case .showOnlySelected:
            return "Show only \(visibleNames)"
        }
    }
}
