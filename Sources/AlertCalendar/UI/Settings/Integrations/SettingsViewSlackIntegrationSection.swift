import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    @ViewBuilder
    func slackIntegrationActionCard(badgeState: SettingsCardBadgeState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if slackShouldUseSideBySideConnectionManagement {
                HStack(alignment: .top, spacing: 14) {
                    slackIntegrationOverview(badgeState: badgeState)
                        .frame(minWidth: 520, maxWidth: .infinity, alignment: .topLeading)

                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 1)

                    slackIntegrationConnectionManagementSection
                        .frame(width: 380, alignment: .topLeading)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    slackIntegrationOverview(badgeState: badgeState)

                    Divider()

                    slackIntegrationStackedConnectionManagement
                }
            }

            Divider()

            slackIntegrationRightColumn
        }
        .settingsPanelSurface(borderColor: badgeState.tint.opacity(0.24))
    }

    @ViewBuilder
    func slackIntegrationOverview(badgeState: SettingsCardBadgeState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            integrationActionCardHeader(for: .slackStatusSync, badgeState: badgeState)

            Text(SettingsIntegrationKind.slackStatusSync.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(integrationDescription(for: .slackStatusSync))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            slackIntegrationStatusMessages
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    var slackIntegrationStackedConnectionManagement: some View {
        if slackConnections.isEmpty {
            slackIntegrationConnectionManagementSection
        } else {
            DisclosureGroup(
                isExpanded: $isShowingSlackConnectionManagement
            ) {
                slackIntegrationConnectionManagement
                    .padding(.top, 10)
            } label: {
                Label("Connection Management", systemImage: "key.horizontal")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    @ViewBuilder
    var slackIntegrationConnectionManagement: some View {
        VStack(alignment: .leading, spacing: 10) {
            slackIntegrationConnectionColumnContent

            integrationActionButtons(for: .slackStatusSync)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var slackIntegrationConnectionManagementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Label("Connection Management", systemImage: "key.horizontal")
                        .font(.subheadline.weight(.semibold))

                    Spacer(minLength: 8)

                    slackOpenAppsButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Connection Management", systemImage: "key.horizontal")
                        .font(.subheadline.weight(.semibold))

                    slackOpenAppsButton
                }
            }

            slackIntegrationConnectionManagement
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    var slackOpenAppsButton: some View {
        Button {
            openSlackAppDashboard()
        } label: {
            Label("Slack Apps…", systemImage: "link")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder
    var slackIntegrationRightColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            slackStatusRulesHeader
            slackStatusRulesListContent
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SlackStatusRulesColumnWidthPreferenceKey.self,
                    value: proxy.size.width
                )
            }
        )
        .onPreferenceChange(SlackStatusRulesColumnWidthPreferenceKey.self) { width in
            guard width > 0, abs(width - slackStatusRulesColumnWidth) > 0.5 else { return }
            slackStatusRulesColumnWidth = width
        }
    }

    var slackWideRuleEditorMinimumColumnWidth: CGFloat {
        1180
    }

    var slackShouldUseSideBySideConnectionManagement: Bool {
        false
    }

    @ViewBuilder
    var slackIntegrationConnectionColumnContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Slack User Token")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                SecureField("xoxp-...", text: $slackUserTokenDraft)
                    .textFieldStyle(.roundedBorder)
            }

            Text("Use an xoxp- token with users.profile:read and users.profile:write, or extract it from the clipboard. Connected tokens are stored in Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var slackIntegrationStatusMessages: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let slackConnectErrorMessage, !slackConnectErrorMessage.isEmpty {
                Text(slackConnectErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let slackError = monitor.slackStatusSyncErrorDescription, !slackError.isEmpty {
                Text(slackError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let slackConnectionStatusMessage, !slackConnectionStatusMessage.isEmpty {
                Text(slackConnectionStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let slackRuntimeStatusDescription, !slackRuntimeStatusDescription.isEmpty {
                Text(slackRuntimeStatusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func integrationBadgeState(for _: SettingsIntegrationKind) -> SettingsCardBadgeState {
        if let slackConnectErrorMessage, !slackConnectErrorMessage.isEmpty {
            return SettingsCardBadgeState(
                title: "Needs Attention",
                tint: Color(red: 0.92, green: 0.31, blue: 0.28)
            )
        }
        if let slackError = monitor.slackStatusSyncErrorDescription, !slackError.isEmpty {
            return SettingsCardBadgeState(
                title: "Needs Attention",
                tint: Color(red: 0.92, green: 0.31, blue: 0.28)
            )
        }
        let enabledRuleCount = slackEnabledStatusRuleCount
        let totalRuleCount = slackConfiguredStatusRuleCount
        if enabledRuleCount > 0 {
            return SettingsCardBadgeState(
                title: enabledRuleCount == 1 ? "1 Active" : "\(enabledRuleCount) Active",
                tint: Color(red: 0.24, green: 0.72, blue: 0.33)
            )
        }
        if totalRuleCount > 0 {
            return SettingsCardBadgeState(
                title: totalRuleCount == 1 ? "1 Rule" : "\(totalRuleCount) Rules",
                tint: Color(red: 0.24, green: 0.59, blue: 0.97)
            )
        }
        if !pendingChanges.slackTokensToConnect.isEmpty
            || !pendingChanges.slackConnectionsToRemove.isEmpty {
            return SettingsCardBadgeState(
                title: "Pending Apply",
                tint: .orange
            )
        }
        if !slackConnections.isEmpty {
            return SettingsCardBadgeState(
                title: "Connected",
                tint: Color(red: 0.24, green: 0.72, blue: 0.33)
            )
        }
        if !slackUserTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return SettingsCardBadgeState(
                title: "Ready to Connect",
                tint: Color(red: 0.24, green: 0.59, blue: 0.97)
            )
        }
        return SettingsCardBadgeState(
            title: "Not Configured",
            tint: .secondary
        )
    }

    @ViewBuilder
    var slackStatusRulesHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Status Rules")
                        .font(.subheadline.weight(.semibold))

                    Text(slackStatusRulesSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                slackConnectedWorkspacesMenu
                slackAddRuleButton
            }

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Status Rules")
                        .font(.subheadline.weight(.semibold))

                    Text(slackStatusRulesSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    slackConnectedWorkspacesMenu
                    slackAddRuleButton
                }
            }
        }
    }

    @ViewBuilder
    var slackStatusRulesListContent: some View {
        if draft.slackStatusSyncRules.isEmpty && slackConnections.isEmpty {
            Text("Connect a Slack workspace to configure calendar and music status rules.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(draft.slackStatusSyncRules.enumerated()), id: \.element.id) { index, rule in
                    slackStatusSyncRuleCard(index: index, rule: rule)
                        .opacity(draggingSlackStatusRuleID == rule.id ? 0.55 : 1)
                        .onDrop(
                            of: [.text],
                            delegate: SlackStatusSyncRuleDropDelegate(
                                targetRuleID: rule.id,
                                rules: $draft.slackStatusSyncRules,
                                draggingRuleID: $draggingSlackStatusRuleID
                            )
                        )
                }

                if !slackConnections.isEmpty {
                    appleMusicStatusRuleCard
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    var slackAddRuleButton: some View {
        Button {
            addSlackStatusSyncRule()
        } label: {
            Label("Add Calendar Rule", systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(
            slackConnections.isEmpty ||
                availableEventCalendars.isEmpty ||
                !hasAvailableSlackStatusSyncPair()
        )
    }

    @ViewBuilder
    var slackConnectedWorkspacesMenu: some View {
        Menu {
            if slackConnections.isEmpty {
                Text("No connected workspaces")
            } else {
                ForEach(slackConnections) { connection in
                    Button(role: .destructive) {
                        removeSlackAccount(connection)
                    } label: {
                        let ruleCount = slackStatusRuleCount(for: connection)
                        if ruleCount > 0 {
                            Text("Disconnect \(connection.workspaceLabel) (\(ruleCount) rule\(ruleCount == 1 ? "" : "s"))")
                        } else {
                            Text("Disconnect \(connection.workspaceLabel)")
                        }
                    }
                }
            }
        } label: {
            Label("Workspaces", systemImage: "building.2")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(slackConnections.isEmpty)
    }

    func slackIntegrationDescription() -> String {
        guard !slackConnections.isEmpty else {
            if slackUserTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Paste a Slack user token, or copy any Slack payload that contains it and use Extract Token."
            }
            return "The token is ready. Connect it to create one or more Slack status sync rules."
        }

        let enabledRuleCount = slackEnabledStatusRuleCount
        let totalRuleCount = slackConfiguredStatusRuleCount

        if totalRuleCount == 0 {
            return "Slack is connected. Configure a music rule or add a calendar rule."
        }

        if enabledRuleCount == 0 {
            return totalRuleCount == 1
                ? "1 Slack sync rule is configured, but it is currently off."
                : "\(totalRuleCount) Slack sync rules are configured, but they are currently off."
        }

        var enabledConnectionIDs = Set(
            draft.slackStatusSyncRules
                .filter { $0.isEnabled && $0.isComplete }
                .map(\.connectionID)
        )
        if draft.appleMusicStatus.isEnabled {
            enabledConnectionIDs.formUnion(draft.appleMusicStatus.connectionIDs)
        }
        let connectedWorkspaceCount = enabledConnectionIDs.count
        return "\(enabledRuleCount) active Slack sync rules across \(connectedWorkspaceCount) workspace\(connectedWorkspaceCount == 1 ? "" : "s")."
    }

    var slackStatusRulesSummary: String {
        let ruleCount = slackConfiguredStatusRuleCount
        var configuredConnectionIDs = Set(draft.slackStatusSyncRules.map(\.connectionID)).subtracting([""])
        configuredConnectionIDs.formUnion(draft.appleMusicStatus.connectionIDs)
        let workspaceCount = configuredConnectionIDs.count

        guard ruleCount > 0 else {
            return "Add calendar rules or configure Apple Music or YouTube Music. Lower priority numbers win when statuses overlap."
        }

        if workspaceCount == 0 {
            return ruleCount == 1 ? "1 rule ready to finish." : "\(ruleCount) rules ready to finish."
        }

        let ruleText = ruleCount == 1 ? "1 rule" : "\(ruleCount) rules"
        let workspaceText = workspaceCount == 1 ? "1 workspace" : "\(workspaceCount) workspaces"
        return "\(ruleText) across \(workspaceText)."
    }

    var slackConfiguredStatusRuleCount: Int {
        draft.slackStatusSyncRules.filter(\.isComplete).count +
            (draft.appleMusicStatus.connectionIDs.isEmpty ? 0 : 1)
    }

    var slackEnabledStatusRuleCount: Int {
        draft.slackStatusSyncRules.filter { $0.isEnabled && $0.isComplete }.count +
            (draft.appleMusicStatus.isEnabled && !draft.appleMusicStatus.connectionIDs.isEmpty ? 1 : 0)
    }
}
