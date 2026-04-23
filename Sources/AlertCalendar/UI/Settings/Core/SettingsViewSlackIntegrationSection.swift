import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    @ViewBuilder
    func slackIntegrationActionCard(badgeState: SettingsCardBadgeState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if slackConnections.isEmpty {
                slackIntegrationLeftColumn(badgeState: badgeState)
            } else if slackShouldUseTwoColumnLayout {
                HStack(alignment: .top, spacing: 18) {
                    slackIntegrationLeftColumn(badgeState: badgeState)
                        .frame(width: slackIntegrationLeftColumnWidth, alignment: .leading)

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1)
                        .padding(.vertical, 4)

                    slackIntegrationRightColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    slackIntegrationLeftColumn(badgeState: badgeState)
                    slackIntegrationRightColumn
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(badgeState.tint.opacity(0.24), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    func slackIntegrationLeftColumn(badgeState: SettingsCardBadgeState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            integrationActionCardHeader(for: .slackStatusSync, badgeState: badgeState)

            Text(SettingsIntegrationKind.slackStatusSync.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(integrationDescription(for: .slackStatusSync))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            slackIntegrationConnectionColumnContent

            integrationActionButtons(for: .slackStatusSync)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var slackIntegrationRightColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            slackStatusRulesHeader
            slackStatusRulesListContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var slackShouldUseTwoColumnLayout: Bool {
        !slackConnections.isEmpty && settingsWindowWidth >= slackTwoColumnMinimumWindowWidth
    }

    var slackTwoColumnMinimumWindowWidth: CGFloat {
        1360
    }

    var slackIntegrationLeftColumnWidth: CGFloat {
        let availableWidth = max(settingsWindowWidth - 40, 0)
        return min(max(availableWidth * 0.33, 500), 640)
    }

    @ViewBuilder
    var slackIntegrationConnectionColumnContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Slack User Token")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                SecureField("xoxp-...", text: $slackUserTokenDraft)
                    .textFieldStyle(.roundedBorder)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Button {
                        openSlackAppDashboard()
                    } label: {
                        Label("Open Slack Apps", systemImage: "link")
                    }
                    .buttonStyle(.bordered)

                    Text("Copy any text that contains the token, then use Extract Token.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        openSlackAppDashboard()
                    } label: {
                        Label("Open Slack Apps", systemImage: "link")
                    }
                    .buttonStyle(.bordered)

                    Text("Copy any text that contains the token, then use Extract Token.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if slackConnections.isEmpty {
                Text("Paste a Slack user token or copy a Slack page payload and use Extract Token. Then choose which account and calendar should drive the status.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            slackIntegrationStatusMessages
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
            } else if let lastSlackStatusSyncDate = monitor.lastSlackStatusSyncDate {
                Text("Last Slack sync: \(Self.settingsDateFormatter.string(from: lastSlackStatusSyncDate))")
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

            Text("Slack status updates still require a user token that starts with xoxp-. AlertCalendar stores the connected token in Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func integrationBadgeState(for integration: SettingsIntegrationKind) -> SettingsCardBadgeState {
        switch integration {
        case .focusFilters:
            if activeFocusCalendarFilterState?.hasActiveOverrides == true {
                return SettingsCardBadgeState(
                    title: "Active",
                    tint: Color(red: 0.24, green: 0.72, blue: 0.33)
                )
            }

            return SettingsCardBadgeState(
                title: "Using Defaults",
                tint: Color(red: 0.24, green: 0.59, blue: 0.97)
            )
        case .slackStatusSync:
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
            let enabledRuleCount = draft.slackStatusSyncRules.filter { $0.isEnabled && $0.isComplete }.count
            let totalRuleCount = draft.slackStatusSyncRules.filter(\.isComplete).count
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
    }

    @ViewBuilder
    var slackStatusRulesHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                Text(slackStatusRulesSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                slackConnectedAccountsMenu
                slackAddRuleButton
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(slackStatusRulesSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    slackConnectedAccountsMenu
                    slackAddRuleButton
                }
            }
        }
    }

    @ViewBuilder
    var slackStatusRulesListContent: some View {
        if draft.slackStatusSyncRules.isEmpty {
            Text("No rules yet. Add one to map a connected Slack account, calendar, and status message.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ForEach(Array(draft.slackStatusSyncRules.enumerated()), id: \.element.id) { index, rule in
                slackStatusSyncRuleCard(index: index, rule: rule)
            }
        }
    }

    @ViewBuilder
    var slackAddRuleButton: some View {
        Button {
            addSlackStatusSyncRule()
        } label: {
            Label("Add Rule", systemImage: "plus")
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
    var slackConnectedAccountsMenu: some View {
        Menu {
            if slackConnections.isEmpty {
                Text("No connected accounts")
            } else {
                ForEach(slackConnections) { connection in
                    Button(role: .destructive) {
                        removeSlackAccount(connection)
                    } label: {
                        let ruleCount = slackStatusRuleCount(for: connection)
                        if ruleCount > 0 {
                            Text("Disconnect \(connection.displayLabel) (\(ruleCount) rule\(ruleCount == 1 ? "" : "s"))")
                        } else {
                            Text("Disconnect \(connection.displayLabel)")
                        }
                    }
                }
            }
        } label: {
            Label("Accounts", systemImage: "person.2")
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
            return "The token is ready. Connect it to create one or more Slack sync rules."
        }

        let enabledRuleCount = draft.slackStatusSyncRules.filter { $0.isEnabled && $0.isComplete }.count
        let totalRuleCount = draft.slackStatusSyncRules.filter(\.isComplete).count

        if totalRuleCount == 0 {
            return "Slack is connected. Add a rule to map each calendar to the Slack account that should receive the meeting status."
        }

        if enabledRuleCount == 0 {
            return totalRuleCount == 1
                ? "1 Slack sync rule is configured, but it is currently off."
                : "\(totalRuleCount) Slack sync rules are configured, but they are currently off."
        }

        let connectedAccountCount = Set(
            draft.slackStatusSyncRules
                .filter { $0.isEnabled && $0.isComplete }
                .map(\.connectionID)
        ).count
        return "\(enabledRuleCount) active Slack sync rules across \(connectedAccountCount) account\(connectedAccountCount == 1 ? "" : "s")."
    }

    var slackStatusRulesSummary: String {
        let ruleCount = draft.slackStatusSyncRules.count
        let accountCount = Set(draft.slackStatusSyncRules.map(\.connectionID)).subtracting([""]).count

        guard ruleCount > 0 else {
            return "Each rule maps one calendar to the Slack account and status message that should be published during a meeting."
        }

        if accountCount == 0 {
            return ruleCount == 1 ? "1 rule ready to finish." : "\(ruleCount) rules ready to finish."
        }

        let ruleText = ruleCount == 1 ? "1 rule" : "\(ruleCount) rules"
        let accountText = accountCount == 1 ? "1 account" : "\(accountCount) accounts"
        return "\(ruleText) across \(accountText)."
    }
}
