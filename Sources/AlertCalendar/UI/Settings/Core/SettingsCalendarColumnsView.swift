import SwiftUI

struct SettingsCalendarColumnsView: View {
    let includeEvents: Bool
    let includeAllDayEvents: Bool
    let includeReminders: Bool
    let availableEventCalendars: [AvailableCalendar]
    let availableReminderCalendars: [AvailableCalendar]
    let onSelectionChanged: () -> Void
    @Binding var selectedEventCalendarIDs: Set<String>
    @Binding var selectedReminderCalendarIDs: Set<String>
    @Binding var weekdayOnlyEventCalendarIDs: Set<String>
    @Binding var weekdayOnlyReminderCalendarIDs: Set<String>

    private let rowHoverBackground = Color.primary.opacity(0.08)
    private let headingColor = Color.secondary
    private let disabledColor = Color.secondary.opacity(0.8)

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                eventSourcesCard
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                reminderSourcesCard
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 16) {
                eventSourcesCard
                reminderSourcesCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var eventSourcesCard: some View {
        sourceCard(
            title: "Calendars",
            subtitle: "Choose which event calendars and all-day sources Alert Calendar should read."
        ) {
            if includeEvents || includeAllDayEvents {
                sourceSection(
                    title: "Event Calendars",
                    calendars: availableEventCalendars,
                    selectedIDs: $selectedEventCalendarIDs,
                    weekdayOnlyIDs: $weekdayOnlyEventCalendarIDs
                )
            } else {
                disabledSection(title: "Event Calendars", message: "Events and all-day events are disabled.")
            }
        }
    }

    private var reminderSourcesCard: some View {
        sourceCard(
            title: "Reminders",
            subtitle: "Pick the reminder lists that can appear in Alert Calendar."
        ) {
            if includeReminders {
                sourceSection(
                    title: "Reminder Lists",
                    calendars: availableReminderCalendars,
                    selectedIDs: $selectedReminderCalendarIDs,
                    weekdayOnlyIDs: $weekdayOnlyReminderCalendarIDs
                )
            } else {
                disabledSection(title: "Reminder Lists", message: "Reminders are disabled.")
            }
        }
    }

    private func sourceCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func sourceSection(
        title: String,
        calendars: [AvailableCalendar],
        selectedIDs: Binding<Set<String>>,
        weekdayOnlyIDs: Binding<Set<String>>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(headingColor)
                .textCase(.uppercase)
                .tracking(0.6)

            calendarItems(
                calendars: calendars,
                selectedIDs: selectedIDs,
                weekdayOnlyIDs: weekdayOnlyIDs
            )
        }
    }

    @ViewBuilder
    private func disabledSection(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(headingColor)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(message)
                .font(.caption)
                .foregroundStyle(disabledColor)
        }
    }

    @ViewBuilder
    private func calendarItems(
        calendars: [AvailableCalendar],
        selectedIDs: Binding<Set<String>>,
        weekdayOnlyIDs: Binding<Set<String>>
    ) -> some View {
        if calendars.isEmpty {
            Text("None found.")
                .font(.caption)
                .foregroundStyle(disabledColor)
        } else {
            let grouped = Dictionary(grouping: calendars, by: \.accountTitle)
            let sortedAccounts = grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(sortedAccounts, id: \.self) { account in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(account)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(headingColor)

                        let items = (grouped[account] ?? [])
                            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

                        ForEach(items) { calendar in
                            SettingsCalendarRowView(
                                calendar: calendar,
                                selectedIDs: selectedIDs,
                                weekdayOnlyIDs: weekdayOnlyIDs,
                                onSelectionChanged: onSelectionChanged,
                                rowHoverBackground: rowHoverBackground
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct SettingsCalendarRowView: View {
    let calendar: AvailableCalendar
    let selectedIDs: Binding<Set<String>>
    let weekdayOnlyIDs: Binding<Set<String>>
    let onSelectionChanged: () -> Void
    let rowHoverBackground: Color
    @State private var isHovered = false

    var body: some View {
        let isSelected = selectedIDs.wrappedValue.contains(calendar.id)
        let isWeekdayOnly = weekdayOnlyIDs.wrappedValue.contains(calendar.id)

        HStack(spacing: 10) {
            Button {
                setCalendarSelection(isSelected: !isSelected)
            } label: {
                HStack(spacing: 11) {
                    checkSquare(color: Color(nsColor: calendar.color.nsColor), isSelected: isSelected)
                    Text(calendar.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isHovered && isSelected ? Color(nsColor: calendar.color.nsColor) : .primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if calendar.isSubscribed {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary.opacity(0.85))
            }

            if isSelected {
                Button {
                    setWeekdayOnly(isWeekdayOnly: !isWeekdayOnly)
                } label: {
                    Text(isWeekdayOnly ? "Weekdays" : "Every day")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isWeekdayOnly ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    isWeekdayOnly
                                        ? Color.accentColor.opacity(0.16)
                                        : Color.secondary.opacity(0.12)
                                )
                        )
                }
                .buttonStyle(.plain)
                .help("Toggle weekdays-only filtering for this calendar")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered ? rowHoverBackground : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func checkSquare(color: Color, isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(isSelected ? color : Color(nsColor: .quaternaryLabelColor).opacity(0.75))
            .frame(width: 16, height: 16)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.86))
                }
            }
    }

    private func setCalendarSelection(isSelected: Bool) {
        if isSelected {
            selectedIDs.wrappedValue.insert(calendar.id)
        } else {
            selectedIDs.wrappedValue.remove(calendar.id)
            weekdayOnlyIDs.wrappedValue.remove(calendar.id)
        }
        onSelectionChanged()
    }

    private func setWeekdayOnly(isWeekdayOnly: Bool) {
        if isWeekdayOnly {
            weekdayOnlyIDs.wrappedValue.insert(calendar.id)
        } else {
            weekdayOnlyIDs.wrappedValue.remove(calendar.id)
        }
        onSelectionChanged()
    }
}
