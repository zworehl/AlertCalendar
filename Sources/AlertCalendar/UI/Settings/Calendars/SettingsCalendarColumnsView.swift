import SwiftUI

struct SettingsCalendarColumnsView: View {
    enum Mode {
        case both
        case eventsOnly
        case remindersOnly
    }

    let mode: Mode
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
    @Binding var calendarAlertRules: [CalendarAlertRule]
    @Binding var meetingBrowserRouting: MeetingBrowserRoutingSettings

    private let headingColor = Color.secondary
    private let disabledColor = Color.secondary.opacity(0.8)

    var body: some View {
        Group {
            switch mode {
            case .both:
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
            case .eventsOnly:
                eventSourcesCard
            case .remindersOnly:
                reminderSourcesCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    var eventSourcesCard: some View {
        sourceCard(
            title: "Event Calendars",
            subtitle: "Choose event sources and configure alert rules independently for each calendar."
        ) {
            if includeEvents || includeAllDayEvents {
                sourceSection(
                    title: "Accounts",
                    calendars: availableEventCalendars,
                    selectedIDs: $selectedEventCalendarIDs,
                    showsMeetingBrowserControls: true
                )
            } else {
                disabledSection(title: "Event Calendars", message: "Events and all-day events are disabled.")
            }
        }
    }

    var reminderSourcesCard: some View {
        sourceCard(
            title: "Reminder Lists",
            subtitle: "Pick the reminder lists that can appear in Alert Calendar."
        ) {
            if includeReminders {
                sourceSection(
                    title: "Accounts",
                    calendars: availableReminderCalendars,
                    selectedIDs: $selectedReminderCalendarIDs,
                    showsMeetingBrowserControls: false
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
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeaderView(title: title, subtitle: subtitle)

            Divider()

            content()
        }
        .settingsPanelSurface()
    }

    @ViewBuilder
    private func sourceSection(
        title: String,
        calendars: [AvailableCalendar],
        selectedIDs: Binding<Set<String>>,
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
                showsMeetingBrowserControls: showsMeetingBrowserControls
            )
        }
    }

    private func accountGroups(
        accounts: [String],
        grouped: [String: [AvailableCalendar]],
        selectedIDs: Binding<Set<String>>,
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
                    onSelectionChanged: onSelectionChanged,
                    calendarAlertRules: showsMeetingBrowserControls ? $calendarAlertRules : nil
                )
            }
        }
    }

    private func sortedCalendars(_ calendars: [AvailableCalendar]) -> [AvailableCalendar] {
        calendars.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
