import SwiftUI

extension SettingsView {
    @ViewBuilder
    func slackStatusSyncRuleTimingEditor(index: Int) -> some View {
        let startsBeforeEvent = draft.slackStatusSyncRules[index].startsBeforeEvent

        VStack(alignment: .leading, spacing: 4) {
            Text("Timing")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Toggle(
                    "Set before event",
                    isOn: $draft.slackStatusSyncRules[index].startsBeforeEvent
                )
                .toggleStyle(.switch)
                .controlSize(.small)

                Picker(
                    "Lead time",
                    selection: $draft.slackStatusSyncRules[index].leadMinutes
                ) {
                    ForEach(AppSettingsRules.slackStatusLeadMinuteOptions, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 92)
                .disabled(!startsBeforeEvent)
                .opacity(startsBeforeEvent ? 1 : 0.55)
            }

            if startsBeforeEvent {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pre-event Text")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField(
                            "Starting soon",
                            text: $draft.slackStatusSyncRules[index].preEventStatusText
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pre-event Emoji")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField(
                            "⏳",
                            text: $draft.slackStatusSyncRules[index].preEventStatusEmoji
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                    .frame(width: 88)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func slackStatusRuleTitle(for rule: SlackStatusSyncRule) -> String {
        slackConnection(for: rule)?.workspaceLabel ?? "Choose Slack workspace"
    }

    func slackStatusRuleSubtitle(for rule: SlackStatusSyncRule) -> String {
        guard let connection = slackConnection(for: rule) else { return "Connect a Slack workspace" }
        return connection.resolvedDisplayName
    }

    func slackStatusRuleCount(for connection: SlackConnection) -> Int {
        draft.slackStatusSyncRules.filter { $0.connectionID == connection.id }.count
    }

    func slackConnection(for rule: SlackStatusSyncRule) -> SlackConnection? {
        slackConnections.first(where: { $0.id == rule.connectionID })
    }

    func slackStatusRuleActiveStatusPreview(for rule: SlackStatusSyncRule) -> String {
        SlackMeetingStatus.statusLine(
            text: rule.statusTextSource == .eventTitle ? "Event Title" : rule.statusText,
            emoji: rule.statusEmoji
        )
    }

    func slackStatusRulePreEventStatusPreview(for rule: SlackStatusSyncRule) -> String {
        SlackMeetingStatus.statusLine(
            text: rule.preEventStatusText,
            emoji: rule.preEventStatusEmoji
        )
    }

    func slackStatusRuleEmojiNeedsPrettyInput(_ rule: SlackStatusSyncRule) -> Bool {
        SlackMeetingStatus.looksLikeSlackAlias(rule.statusEmoji) ||
            SlackMeetingStatus.looksLikeSlackAlias(rule.preEventStatusEmoji)
    }

    @ViewBuilder
    func slackStatusRuleStatusPreviews(for rule: SlackStatusSyncRule) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 6) {
                if rule.startsBeforeEvent {
                    slackStatusRuleStatusPreview(
                        label: "Starting soon · \(rule.leadMinutes) min",
                        status: slackStatusRulePreEventStatusPreview(for: rule)
                    )
                }

                slackStatusRuleStatusPreview(
                    label: "In progress",
                    status: slackStatusRuleActiveStatusPreview(for: rule)
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                if rule.startsBeforeEvent {
                    slackStatusRuleStatusPreview(
                        label: "Starting soon · \(rule.leadMinutes) min",
                        status: slackStatusRulePreEventStatusPreview(for: rule)
                    )
                }

                slackStatusRuleStatusPreview(
                    label: "In progress",
                    status: slackStatusRuleActiveStatusPreview(for: rule)
                )
            }
        }
    }

    @ViewBuilder
    func slackStatusRuleStatusPreview(label: String, status: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(status)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    func slackWorkspaceBadge(for rule: SlackStatusSyncRule) -> some View {
        let connection = slackConnection(for: rule)

        SlackWorkspaceAvatarPair(
            primaryImageURL: connection?.profileImageURL,
            secondaryImageURL: connection?.workspaceImageURL,
            primaryInitials: initials(for: connection?.resolvedDisplayName),
            secondaryInitials: initials(for: connection?.workspaceLabel)
        )
        .equatable()
    }

    func initials(for value: String?) -> String {
        let components = (value ?? "")
            .split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "-" })
            .prefix(2)

        return components.compactMap { component in
            component.first.map { String($0).uppercased() }
        }.joined()
    }
}
