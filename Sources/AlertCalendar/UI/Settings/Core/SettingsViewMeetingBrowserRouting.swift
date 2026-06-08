import SwiftUI

extension SettingsView {
    @ViewBuilder
    var meetingBrowserRoutingSettingsContent: some View {
        GroupBox("Meeting Links") {
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
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    )
            )
        }
        .frame(width: 220)
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    func meetingBrowserProfilePicker(route: Binding<MeetingBrowserRoute>) -> some View {
        let browser = route.wrappedValue.browser
        let options = meetingBrowserProfileOptions(for: browser, selectedProfileID: route.wrappedValue.profileID)

        if browser.profileFamily == .none || options.count <= 1 {
            HStack(spacing: 8) {
                Text("Profile")
                    .foregroundStyle(.secondary)

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
            .font(.caption)
        } else {
            Picker("Profile", selection: meetingBrowserProfileBinding(for: route)) {
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
