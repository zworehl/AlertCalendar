import SwiftUI

struct SettingsCalendarAccountBrowserControls: View {
    let accountTitle: String
    let calendars: [AvailableCalendar]
    let installedMeetingBrowsers: [MeetingBrowserKind]
    let profilesByBrowser: [MeetingBrowserKind: [MeetingBrowserProfileOption]]
    let profileIssuesByBrowser: [MeetingBrowserKind: MeetingBrowserProfileLoadIssue]
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
            .frame(minHeight: SettingsVisualMetrics.minimumInteractiveControlSize)
            .background(SettingsControlChrome())
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Browser for \(accountTitle)")
    }

    @ViewBuilder
    private var profilePicker: some View {
        if let selectedBrowser {
            let options = profileOptions(for: selectedBrowser)
            if selectedBrowser.profileFamily == .none {
                Text("Automatic")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 104, alignment: .leading)
            } else if options.count <= 1 {
                Text(profileIssuesByBrowser[selectedBrowser] == nil ? options[0].displayName : "Unavailable")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        profileIssuesByBrowser[selectedBrowser] == nil
                            ? Color.secondary
                            : Color.red
                    )
                    .frame(width: 104, alignment: .leading)
                    .help(profileIssuesByBrowser[selectedBrowser]?.message ?? options[0].detailText)
            } else {
                Picker("\(selectedBrowser.title) profile", selection: profileBinding(for: selectedBrowser)) {
                    ForEach(options) { profile in
                        Text(profile.displayName).tag(profile.id)
                    }
                }
                .labelsHidden()
                .frame(width: 132)
                .controlSize(.small)
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
