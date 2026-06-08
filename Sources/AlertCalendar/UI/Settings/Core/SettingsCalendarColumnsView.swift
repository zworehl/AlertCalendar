import AppKit
import SwiftUI

struct SettingsCalendarColumnsView: View {
    let includeEvents: Bool
    let includeAllDayEvents: Bool
    let includeReminders: Bool
    let availableEventCalendars: [AvailableCalendar]
    let availableReminderCalendars: [AvailableCalendar]
    let installedMeetingBrowsers: [MeetingBrowserKind]
    let meetingBrowserProfilesByBrowser: [MeetingBrowserKind: [MeetingBrowserProfileOption]]
    let onSelectionChanged: () -> Void
    @Binding var selectedEventCalendarIDs: Set<String>
    @Binding var selectedReminderCalendarIDs: Set<String>
    @Binding var weekdayOnlyEventCalendarIDs: Set<String>
    @Binding var weekdayOnlyReminderCalendarIDs: Set<String>
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
            subtitle: "Choose which event calendars and all-day sources Alert Calendar should read."
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(headingColor.opacity(0.9))
                    .lineLimit(1)

                Spacer(minLength: 6)

                if showsMeetingBrowserControls {
                    SettingsCalendarAccountBrowserControls(
                        accountTitle: ruleTitle,
                        calendars: items,
                        installedMeetingBrowsers: installedMeetingBrowsers,
                        profilesByBrowser: meetingBrowserProfilesByBrowser,
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
                    rowHoverBackground: rowHoverBackground
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

private struct SettingsCalendarAccountBrowserControls: View {
    let accountTitle: String
    let calendars: [AvailableCalendar]
    let installedMeetingBrowsers: [MeetingBrowserKind]
    let profilesByBrowser: [MeetingBrowserKind: [MeetingBrowserProfileOption]]
    @Binding var meetingBrowserRouting: MeetingBrowserRoutingSettings

    private var calendarIDs: Set<String> {
        Set(calendars.map(\.id))
    }

    private var ruleID: String {
        "calendar-account:\(accountTitle)"
    }

    private var selectedRoute: MeetingBrowserRoute? {
        if let accountRule = meetingBrowserRouting.rules.first(where: { $0.id == ruleID && $0.isEnabled }) {
            return installedRoute(accountRule.route)
        }

        guard let matchingRule = meetingBrowserRouting.rules.first(where: { rule in
            rule.isEnabled && !rule.calendarIDs.isDisjoint(with: calendarIDs)
        }) else {
            return nil
        }

        return installedRoute(matchingRule.route)
    }

    private var selectedBrowser: MeetingBrowserKind? {
        selectedRoute?.browser
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            browserMenu
            profilePicker
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var browserMenu: some View {
        Menu {
            Button {
                removeAccountRule()
            } label: {
                HStack {
                    Text("Default")
                    if selectedBrowser == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            if !installedMeetingBrowsers.isEmpty {
                Divider()
            }

            ForEach(installedMeetingBrowsers) { browser in
                Button {
                    setBrowser(browser)
                } label: {
                    HStack {
                        MeetingBrowserIconView(browser: browser)
                        Text(browser.title)
                        if selectedBrowser == browser {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                if let selectedBrowser {
                    MeetingBrowserIconView(browser: selectedBrowser)
                    Text(selectedBrowser.title)
                } else {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Default")
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private var profilePicker: some View {
        if let selectedBrowser {
            let options = profileOptions(for: selectedBrowser)
            if selectedBrowser.profileFamily == .none || options.count <= 1 {
                Text("Automatic")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 104, alignment: .leading)
            } else {
                Picker("\(selectedBrowser.title) profile", selection: profileBinding(for: selectedBrowser)) {
                    ForEach(options) { profile in
                        Text(profile.displayName).tag(profile.id)
                    }
                }
                .labelsHidden()
                .frame(width: 132)
            }
        } else {
            Text("Default")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 104, alignment: .leading)
        }
    }

    private func profileBinding(for browser: MeetingBrowserKind) -> Binding<String> {
        Binding(
            get: {
                if selectedRoute?.browser == browser {
                    return selectedRoute?.profileID ?? defaultProfileID(for: browser)
                }

                return defaultProfileID(for: browser)
            },
            set: { profileID in
                setRoute(MeetingBrowserRoute(browser: browser, profileID: profileID))
            }
        )
    }

    private func setBrowser(_ browser: MeetingBrowserKind) {
        setRoute(
            MeetingBrowserRoute(
                browser: browser,
                profileID: defaultProfileID(for: browser)
            )
        )
    }

    private func setRoute(_ route: MeetingBrowserRoute) {
        guard !calendarIDs.isEmpty else { return }

        var rules = meetingBrowserRouting.rules.filter { rule in
            rule.id != ruleID && rule.calendarIDs.isDisjoint(with: calendarIDs)
        }

        rules.append(
            CalendarMeetingBrowserRule(
                id: ruleID,
                name: accountTitle,
                calendarIDs: calendarIDs,
                route: route.normalized,
                isEnabled: true
            )
        )

        meetingBrowserRouting.rules = rules
    }

    private func removeAccountRule() {
        meetingBrowserRouting.rules.removeAll { rule in
            rule.id == ruleID || !rule.calendarIDs.isDisjoint(with: calendarIDs)
        }
    }

    private func defaultProfileID(for browser: MeetingBrowserKind) -> String {
        switch browser.profileFamily {
        case .chromium:
            return profileOptions(for: browser).first?.id ?? MeetingBrowserRoute.defaultChromeProfileID
        case .firefox:
            return profileOptions(for: browser).first?.id ?? MeetingBrowserRoute.defaultFirefoxProfileID
        case .none:
            return MeetingBrowserRoute.automaticProfileID
        }
    }

    private func profileOptions(for browser: MeetingBrowserKind) -> [MeetingBrowserProfileOption] {
        var profiles = profilesByBrowser[browser] ?? [MeetingBrowserProfileOption.automatic(for: browser)]
        let selectedID = selectedRoute?.browser == browser
            ? selectedRoute?.profileID ?? defaultProfileFallbackID(for: browser)
            : defaultProfileFallbackID(for: browser)

        if !profiles.contains(where: { $0.id == selectedID }) {
            profiles.append(
                MeetingBrowserProfileOption(
                    id: selectedID,
                    displayName: selectedID,
                    detailText: selectedID,
                    isDefault: false
                )
            )
        }

        return profiles
    }

    private func defaultProfileFallbackID(for browser: MeetingBrowserKind) -> String {
        switch browser.profileFamily {
        case .chromium:
            return MeetingBrowserRoute.defaultChromeProfileID
        case .firefox:
            return MeetingBrowserRoute.defaultFirefoxProfileID
        case .none:
            return MeetingBrowserRoute.automaticProfileID
        }
    }

    private func installedRoute(_ route: MeetingBrowserRoute) -> MeetingBrowserRoute? {
        let normalizedRoute = route.normalized
        guard installedMeetingBrowsers.contains(normalizedRoute.browser) else { return nil }
        return normalizedRoute
    }
}

struct MeetingBrowserIconView: View {
    let browser: MeetingBrowserKind

    var body: some View {
        if let icon = Self.icon(for: browser) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: fallbackSymbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var fallbackSymbolName: String {
        switch browser {
        case .chrome, .edge, .brave, .vivaldi, .chromium, .arc, .opera, .duckDuckGo, .orion:
            return "circle.hexagongrid.circle"
        case .safari:
            return "safari"
        case .firefox, .firefoxDeveloperEdition, .librewolf, .floorp, .zen:
            return "flame"
        }
    }

    private static func icon(for browser: MeetingBrowserKind) -> NSImage? {
        guard let appURL = MeetingBrowserCatalog.applicationURL(for: browser) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: appURL.path)
        image.isTemplate = false
        image.size = NSSize(width: 32, height: 32)
        return image
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

        HStack(spacing: 8) {
            Button {
                setCalendarSelection(isSelected: !isSelected)
            } label: {
                HStack(spacing: 9) {
                    checkSquare(color: Color(nsColor: calendar.color.nsColor), isSelected: isSelected)
                    Text(calendar.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isHovered && isSelected ? Color(nsColor: calendar.color.nsColor) : .primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if calendar.isSubscribed {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary.opacity(0.85))
            }

            if isSelected {
                Button {
                    setWeekdayOnly(isWeekdayOnly: !isWeekdayOnly)
                } label: {
                    Text(isWeekdayOnly ? "Weekdays" : "Every day")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isWeekdayOnly ? .primary : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? rowHoverBackground : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func checkSquare(color: Color, isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color)
            .frame(width: 16, height: 16)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
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
