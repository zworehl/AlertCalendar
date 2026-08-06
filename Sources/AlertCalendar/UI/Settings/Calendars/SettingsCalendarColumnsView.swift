import SwiftUI

struct SettingsCalendarColumnsView: View {
    let includeEvents: Bool
    let includeAllDayEvents: Bool
    let includeReminders: Bool
    let availableEventCalendars: [AvailableCalendar]
    let availableReminderCalendars: [AvailableCalendar]
    let installedMeetingBrowsers: [MeetingBrowserKind]
    let meetingBrowserProfilesByBrowser: [MeetingBrowserKind: [MeetingBrowserProfileOption]]
    let meetingBrowserProfileIssuesByBrowser: [MeetingBrowserKind: MeetingBrowserProfileLoadIssue]
    let onSelectionChanged: () -> Void
    @Binding var selectedEventCalendarIDs: Set<String>
    @Binding var selectedReminderCalendarIDs: Set<String>
    @Binding var weekdayOnlyEventCalendarIDs: Set<String>
    @Binding var weekdayOnlyReminderCalendarIDs: Set<String>
    @Binding var calendarAlertRules: [CalendarAlertRule]
    @Binding var meetingBrowserRouting: MeetingBrowserRoutingSettings

    private let rowHoverBackground = Color.primary.opacity(0.08)
    private let headingColor = Color.secondary
    private let disabledColor = Color.secondary.opacity(0.8)

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                eventSourcesCard
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                rightSourcesColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 16) {
                eventSourcesCard
                rightSourcesColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var primaryEventCalendars: [AvailableCalendar] {
        availableEventCalendars.filter { !isOtherAccountTitle($0.accountTitle) }
    }

    private var otherEventCalendars: [AvailableCalendar] {
        availableEventCalendars.filter { isOtherAccountTitle($0.accountTitle) }
    }

    private var eventSourcesCard: some View {
        sourceCard(
            title: "Calendars",
            subtitle: "Choose event sources and configure alert rules independently for each calendar."
        ) {
            if includeEvents || includeAllDayEvents {
                sourceSection(
                    title: "Event Calendars",
                    calendars: primaryEventCalendars,
                    selectedIDs: $selectedEventCalendarIDs,
                    weekdayOnlyIDs: $weekdayOnlyEventCalendarIDs,
                    showsMeetingBrowserControls: true
                )
            } else {
                disabledSection(title: "Event Calendars", message: "Events and all-day events are disabled.")
            }
        }
    }

    private var rightSourcesColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            reminderSourcesCard

            if includeEvents || includeAllDayEvents, !otherEventCalendars.isEmpty {
                otherEventSourcesCard
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
                    weekdayOnlyIDs: $weekdayOnlyReminderCalendarIDs,
                    showsMeetingBrowserControls: false
                )
            } else {
                disabledSection(title: "Reminder Lists", message: "Reminders are disabled.")
            }
        }
    }

    private var otherEventSourcesCard: some View {
        sourceCard(
            title: "Others",
            subtitle: "Event calendars that are not attached to a named calendar account."
        ) {
            accountGroup(
                title: "Event Calendars",
                ruleTitle: "Other Account",
                items: sortedCalendars(otherEventCalendars),
                selectedIDs: $selectedEventCalendarIDs,
                weekdayOnlyIDs: $weekdayOnlyEventCalendarIDs,
                showsMeetingBrowserControls: true
            )
        }
    }

    private func sourceCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeaderView(title: title, subtitle: subtitle)

            Divider()

            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func sourceSection(
        title: String,
        calendars: [AvailableCalendar],
        selectedIDs: Binding<Set<String>>,
        weekdayOnlyIDs: Binding<Set<String>>,
        showsMeetingBrowserControls: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(headingColor)
                .textCase(.uppercase)
                .tracking(0.6)

            calendarItems(
                calendars: calendars,
                selectedIDs: selectedIDs,
                weekdayOnlyIDs: weekdayOnlyIDs,
                showsMeetingBrowserControls: showsMeetingBrowserControls
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
        weekdayOnlyIDs: Binding<Set<String>>,
        showsMeetingBrowserControls: Bool
    ) -> some View {
        if calendars.isEmpty {
            Text("None found.")
                .font(.caption)
                .foregroundStyle(disabledColor)
        } else {
            let grouped = Dictionary(grouping: calendars, by: \.accountTitle)
            let sortedAccounts = grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

            accountGroups(
                accounts: sortedAccounts,
                grouped: grouped,
                selectedIDs: selectedIDs,
                weekdayOnlyIDs: weekdayOnlyIDs,
                showsMeetingBrowserControls: showsMeetingBrowserControls
            )
        }
    }

    private func accountGroups(
        accounts: [String],
        grouped: [String: [AvailableCalendar]],
        selectedIDs: Binding<Set<String>>,
        weekdayOnlyIDs: Binding<Set<String>>,
        showsMeetingBrowserControls: Bool
    ) -> some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(accounts, id: \.self) { account in
                let items = sortedCalendars(grouped[account] ?? [])

                accountGroup(
                    title: account,
                    ruleTitle: account,
                    items: items,
                    selectedIDs: selectedIDs,
                    weekdayOnlyIDs: weekdayOnlyIDs,
                    showsMeetingBrowserControls: showsMeetingBrowserControls
                )
            }
        }
    }

    private func accountGroup(
        title: String,
        ruleTitle: String,
        items: [AvailableCalendar],
        selectedIDs: Binding<Set<String>>,
        weekdayOnlyIDs: Binding<Set<String>>,
        showsMeetingBrowserControls: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(SettingsTypography.itemTitle)
                    .foregroundStyle(headingColor.opacity(0.9))
                    .lineLimit(1)

                Spacer(minLength: 6)

                if showsMeetingBrowserControls {
                    SettingsCalendarAccountBrowserControls(
                        accountTitle: ruleTitle,
                        calendars: items,
                        installedMeetingBrowsers: installedMeetingBrowsers,
                        profilesByBrowser: meetingBrowserProfilesByBrowser,
                        profileIssuesByBrowser: meetingBrowserProfileIssuesByBrowser,
                        meetingBrowserRouting: $meetingBrowserRouting
                    )
                }
            }

            ForEach(items) { calendar in
                SettingsCalendarRowView(
                    calendar: calendar,
                    selectedIDs: selectedIDs,
                    weekdayOnlyIDs: weekdayOnlyIDs,
                    onSelectionChanged: onSelectionChanged,
                    rowHoverBackground: rowHoverBackground,
                    calendarAlertRules: showsMeetingBrowserControls ? $calendarAlertRules : nil
                )
            }
        }
    }

    private func sortedCalendars(_ calendars: [AvailableCalendar]) -> [AvailableCalendar] {
        calendars.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func isOtherAccountTitle(_ title: String) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedTitle == "other"
            || normalizedTitle == "others"
            || normalizedTitle == "other account"
    }
}
