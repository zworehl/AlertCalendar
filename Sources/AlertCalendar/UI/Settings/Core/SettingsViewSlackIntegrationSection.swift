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
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var slackShouldUseTwoColumnLayout: Bool {
        !slackConnections.isEmpty && settingsWindowWidth >= slackTwoColumnMinimumWindowWidth
    }

    var slackTwoColumnMinimumWindowWidth: CGFloat {
        1360
    }

    var slackIntegrationLeftColumnWidth: CGFloat {
        let availableWidth = max(settingsWindowWidth - 40, 0)
        return min(max(availableWidth * 0.28, 420), 560)
    }

    var slackShouldUseRuleGrid: Bool {
        slackShouldUseTwoColumnLayout && settingsWindowWidth >= 1700
    }

    var slackStatusRulesListMaxHeight: CGFloat {
        slackShouldUseRuleGrid ? 340 : 520
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
                Text("Paste a Slack user token or copy a Slack page payload and use Extract Token. Then choose which workspace and calendar should drive the status.")
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

                slackConnectedWorkspacesMenu
                slackAddRuleButton
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(slackStatusRulesSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    slackConnectedWorkspacesMenu
                    slackAddRuleButton
                }
            }
        }
    }

    @ViewBuilder
    var slackStatusRulesListContent: some View {
        if draft.slackStatusSyncRules.isEmpty {
            Text("No rules yet. Add one to map a connected Slack workspace, calendar, and status message.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ScrollView(.vertical) {
                LazyVGrid(columns: slackStatusRulesGridColumns, alignment: .leading, spacing: 12) {
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
                }
                .padding(.trailing, 4)
                .padding(.bottom, 2)
            }
            .scrollIndicators(.automatic)
            .frame(maxWidth: .infinity, maxHeight: slackStatusRulesListMaxHeight, alignment: .topLeading)
        }
    }

    var slackStatusRulesGridColumns: [GridItem] {
        if slackShouldUseRuleGrid {
            return [
                GridItem(.flexible(minimum: 440), spacing: 12),
                GridItem(.flexible(minimum: 440), spacing: 12)
            ]
        }
        return [GridItem(.flexible(minimum: 0), spacing: 12)]
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
            return "The token is ready. Connect it to create one or more Slack sync rules."
        }

        let enabledRuleCount = draft.slackStatusSyncRules.filter { $0.isEnabled && $0.isComplete }.count
        let totalRuleCount = draft.slackStatusSyncRules.filter(\.isComplete).count

        if totalRuleCount == 0 {
            return "Slack is connected. Add a rule to map each calendar to the Slack workspace that should receive the meeting status."
        }

        if enabledRuleCount == 0 {
            return totalRuleCount == 1
                ? "1 Slack sync rule is configured, but it is currently off."
                : "\(totalRuleCount) Slack sync rules are configured, but they are currently off."
        }

        let connectedWorkspaceCount = Set(
            draft.slackStatusSyncRules
                .filter { $0.isEnabled && $0.isComplete }
                .map(\.connectionID)
        ).count
        return "\(enabledRuleCount) active Slack sync rules across \(connectedWorkspaceCount) workspace\(connectedWorkspaceCount == 1 ? "" : "s")."
    }

    var slackStatusRulesSummary: String {
        let ruleCount = draft.slackStatusSyncRules.count
        let workspaceCount = Set(draft.slackStatusSyncRules.map(\.connectionID)).subtracting([""]).count

        guard ruleCount > 0 else {
            return "Each rule maps one calendar to the Slack workspace and status message that should be published during a meeting."
        }

        if workspaceCount == 0 {
            return ruleCount == 1 ? "1 rule ready to finish." : "\(ruleCount) rules ready to finish."
        }

        let ruleText = ruleCount == 1 ? "1 rule" : "\(ruleCount) rules"
        let workspaceText = workspaceCount == 1 ? "1 workspace" : "\(workspaceCount) workspaces"
        return "\(ruleText) across \(workspaceText)."
    }
}

private struct SlackStatusSyncRuleDropDelegate: DropDelegate {
    let targetRuleID: String
    @Binding var rules: [SlackStatusSyncRule]
    @Binding var draggingRuleID: String?

    func validateDrop(info: DropInfo) -> Bool {
        draggingRuleID != nil
    }

    func dropEntered(info: DropInfo) {
        moveDraggingRuleIfNeeded()
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingRuleID = nil
        return true
    }

    private func moveDraggingRuleIfNeeded() {
        guard let draggingRuleID, draggingRuleID != targetRuleID else { return }
        guard let sourceIndex = rules.firstIndex(where: { $0.id == draggingRuleID }) else { return }
        guard let targetIndex = rules.firstIndex(where: { $0.id == targetRuleID }) else { return }

        withAnimation(.easeInOut(duration: 0.14)) {
            rules.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }
    }
}
