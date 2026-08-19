import SwiftUI

extension SettingsView {
    @ViewBuilder
    var meetingBrowserProfileIssuesBanner: some View {
        if !meetingBrowserProfileIssues.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Browser profiles are unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)

                ForEach(meetingBrowserProfileIssues) { issue in
                    Text(issue.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .help("\(issue.sourcePath)\n\(issue.technicalDescription)")
                }

                Text("Manage browser profile access from the Access section. Browser routing continues to use the saved fallback profile until access is restored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        withAnimation {
                            selectedTab = .access
                        }
                    } label: {
                        Label("Review in Access", systemImage: "lock.shield")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        refreshMeetingBrowserProfiles()
                    } label: {
                        Label("Retry Profiles", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .settingsPanelSurface(
                fill: Color.orange.opacity(0.09),
                borderColor: Color.orange.opacity(0.3)
            )
        }
    }

    @ViewBuilder
    var meetingBrowserRoutingSettingsContent: some View {
        settingsSection(
            title: "Meeting Links",
            subtitle: "Choose the fallback browser and profile for video meeting links.",
            systemImage: "link"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Fallback Browser")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                meetingBrowserRouteControls(route: $draft.meetingBrowserRouting.defaultRoute)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    func meetingBrowserRouteControls(route: Binding<MeetingBrowserRoute>) -> some View {
        let installedRoute = installedMeetingBrowserRouteBinding(for: route)

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                meetingBrowserPicker(route: installedRoute)
                meetingBrowserProfilePicker(route: installedRoute)
            }

            VStack(alignment: .leading, spacing: 8) {
                meetingBrowserPicker(route: installedRoute)
                meetingBrowserProfilePicker(route: installedRoute)
            }
        }
    }

    @ViewBuilder
    func meetingBrowserPicker(route: Binding<MeetingBrowserRoute>) -> some View {
        Menu {
            if installedMeetingBrowsers.isEmpty {
                Text("No supported browsers installed")
            }

            ForEach(installedMeetingBrowsers) { browser in
                Button {
                    route.wrappedValue = MeetingBrowserRoute(
                        browser: browser,
                        profileID: defaultMeetingBrowserProfileID(for: browser)
                    ).normalized
                } label: {
                    HStack {
                        MeetingBrowserIconView(browser: browser)
                        Text(browser.title)
                        if route.wrappedValue.browser == browser {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                MeetingBrowserIconView(browser: route.wrappedValue.browser)
                Text(route.wrappedValue.browser.title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(SettingsControlChrome())
        }
        .frame(width: 220)
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    func meetingBrowserProfilePicker(route: Binding<MeetingBrowserRoute>) -> some View {
        let browser = route.wrappedValue.browser
        let options = meetingBrowserProfileOptions(for: browser, selectedProfileID: route.wrappedValue.profileID)

        if browser.profileFamily == .none {
            SettingsLabeledControl(
                title: "Profile",
                layout: .inline(labelWidth: 48)
            ) {
                Text("Automatic")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }
            .frame(width: 260)
        } else if options.count <= 1 {
            SettingsLabeledControl(
                title: "Profile",
                layout: .inline(labelWidth: 48)
            ) {
                Text(meetingBrowserProfileIssuesByBrowser[browser] == nil ? options[0].displayName : "Unavailable")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        meetingBrowserProfileIssuesByBrowser[browser] == nil
                            ? Color.secondary
                            : Color.red
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    )
                    .help(meetingBrowserProfileIssuesByBrowser[browser]?.message ?? options[0].detailText)
            }
            .frame(width: 260)
        } else {
            SettingsLabeledMenuPicker(
                title: "Profile",
                pickerTitle: "Meeting browser profile",
                selection: meetingBrowserProfileBinding(for: route),
                layout: .inline(labelWidth: 48)
            ) {
                ForEach(options) { profile in
                    Text(profile.displayName).tag(profile.id)
                }
            }
            .frame(width: 260)
            .help(meetingBrowserProfileHelpText(for: route.wrappedValue))
        }
    }

    func installedMeetingBrowserRouteBinding(for route: Binding<MeetingBrowserRoute>) -> Binding<MeetingBrowserRoute> {
        Binding(
            get: {
                let normalizedRoute = route.wrappedValue.normalized
                guard installedMeetingBrowsers.contains(normalizedRoute.browser) else {
                    guard let browser = installedMeetingBrowsers.first else {
                        return normalizedRoute
                    }

                    return MeetingBrowserRoute(
                        browser: browser,
                        profileID: defaultMeetingBrowserProfileID(for: browser)
                    ).normalized
                }

                return normalizedRoute
            },
            set: { updatedRoute in
                route.wrappedValue = updatedRoute.normalized
            }
        )
    }

    func meetingBrowserProfileBinding(for route: Binding<MeetingBrowserRoute>) -> Binding<String> {
        Binding(
            get: {
                let profileID = route.wrappedValue.profileID
                if profileID == MeetingBrowserRoute.automaticProfileID {
                    return defaultMeetingBrowserProfileID(for: route.wrappedValue.browser)
                }

                return profileID
            },
            set: { profileID in
                var updatedRoute = route.wrappedValue
                updatedRoute.profileID = profileID
                route.wrappedValue = updatedRoute.normalized
            }
        )
    }

    func defaultMeetingBrowserProfileID(for browser: MeetingBrowserKind) -> String {
        switch browser.profileFamily {
        case .chromium:
            return meetingBrowserProfileOptions(for: browser, selectedProfileID: MeetingBrowserRoute.defaultChromeProfileID).first?.id
                ?? MeetingBrowserRoute.defaultChromeProfileID
        case .firefox:
            return meetingBrowserProfileOptions(for: browser, selectedProfileID: MeetingBrowserRoute.defaultFirefoxProfileID).first?.id
                ?? MeetingBrowserRoute.defaultFirefoxProfileID
        case .none:
            return MeetingBrowserRoute.automaticProfileID
        }
    }

    func meetingBrowserProfileOptions(
        for browser: MeetingBrowserKind,
        selectedProfileID: String
    ) -> [MeetingBrowserProfileOption] {
        if browser.profileFamily == .none {
            return [MeetingBrowserProfileOption.automatic(for: browser)]
        }

        var profiles = meetingBrowserProfilesByBrowser[browser] ?? [MeetingBrowserProfileOption.automatic(for: browser)]
        let selectedID: String
        if selectedProfileID == MeetingBrowserRoute.automaticProfileID {
            selectedID = browser.profileFamily == .firefox
                ? MeetingBrowserRoute.defaultFirefoxProfileID
                : MeetingBrowserRoute.defaultChromeProfileID
        } else {
            selectedID = selectedProfileID
        }

        if !selectedID.isEmpty, !profiles.contains(where: { $0.id == selectedID }) {
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

    func meetingBrowserProfileHelpText(for route: MeetingBrowserRoute) -> String {
        let normalizedRoute = route.normalized
        let selectedID = normalizedRoute.profileID == MeetingBrowserRoute.automaticProfileID
            ? defaultMeetingBrowserProfileID(for: normalizedRoute.browser)
            : normalizedRoute.profileID
        guard let profile = meetingBrowserProfileOptions(
            for: normalizedRoute.browser,
            selectedProfileID: selectedID
        ).first(where: { $0.id == selectedID }) else {
            return selectedID
        }

        return profile.detailText
    }
}
