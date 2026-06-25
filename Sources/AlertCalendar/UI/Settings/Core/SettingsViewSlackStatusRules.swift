import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    @ViewBuilder
    func slackStatusSyncRuleCard(index: Int, rule: SlackStatusSyncRule) -> some View {
        let isComplete = !draft.slackStatusSyncRules[index].connectionID.isEmpty &&
            !draft.slackStatusSyncRules[index].calendarID.isEmpty

        VStack(alignment: .leading, spacing: 10) {
            slackStatusSyncRuleHeader(index: index, rule: rule, isComplete: isComplete)

            if slackShouldUseWideRuleEditors {
                slackStatusSyncRuleWideEditors(index: index)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    slackStatusSyncRuleEditors(index: index)
                }
            }

            if slackStatusRuleEmojiNeedsPrettyInput(rule) {
                Text("Use an actual emoji like 🐶 or 🗓️ here. Known Slack aliases are auto-converted when possible, but the field looks better with emoji characters.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    func slackStatusSyncRuleHeader(index: Int, rule: SlackStatusSyncRule, isComplete: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            slackStatusSyncRuleDragHandle(for: rule)

            slackStatusSyncRuleIdentity(for: rule)

            Spacer(minLength: 0)

            slackStatusSyncRuleActionBar(index: index, rule: rule, isComplete: isComplete)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    func slackStatusSyncRuleActionBar(index: Int, rule: SlackStatusSyncRule, isComplete: Bool) -> some View {
        HStack(spacing: 10) {
            Text("#\(index + 1)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 24)
                .help("Priority \(index + 1)")

            Toggle("Active", isOn: $draft.slackStatusSyncRules[index].isEnabled)
                .font(.caption)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!isComplete)

            Button(role: .destructive) {
                removeSlackStatusSyncRule(rule.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Remove")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    func slackStatusSyncRuleDragHandle(for rule: SlackStatusSyncRule) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 34)
            .contentShape(Rectangle())
            .help("Drag to set priority")
            .onDrag {
                draggingSlackStatusRuleID = rule.id
                return NSItemProvider(object: rule.id as NSString)
            }
            .accessibilityLabel("Priority handle")
    }

    @ViewBuilder
    func slackStatusSyncRuleEditors(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if slackShouldUseInlineRuleEditorRows {
                HStack(alignment: .top, spacing: 10) {
                    slackStatusSyncRuleConnectionPicker(index: index)
                        .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

                    slackStatusSyncRuleCalendarPicker(index: index)
                        .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    slackStatusSyncRuleConnectionPicker(index: index)
                    slackStatusSyncRuleCalendarPicker(index: index)
                }
            }
            if slackShouldUseInlineRuleEditorRows {
                HStack(alignment: .top, spacing: 10) {
                    slackStatusSyncRuleTextSourcePicker(index: index)
                    if draft.slackStatusSyncRules[index].statusTextSource == .fixed {
                        slackStatusSyncRuleTextField(index: index)
                    }
                    slackStatusSyncRuleEmojiField(index: index)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    slackStatusSyncRuleTextSourcePicker(index: index)
                    if draft.slackStatusSyncRules[index].statusTextSource == .fixed {
                        slackStatusSyncRuleTextField(index: index)
                    }
                    slackStatusSyncRuleEmojiField(index: index)
                }
            }
        }
    }

    var slackShouldUseWideRuleEditors: Bool {
        settingsWindowWidth >= slackTwoColumnMinimumWindowWidth && !slackShouldUseRuleGrid
    }

    var slackShouldUseInlineRuleEditorRows: Bool {
        settingsWindowWidth >= 980
    }

    @ViewBuilder
    func slackStatusSyncRuleWideEditors(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                slackStatusSyncRuleConnectionPicker(index: index)
                    .frame(width: 260, alignment: .leading)

                slackStatusSyncRuleCalendarPicker(index: index)
                    .frame(minWidth: 260, maxWidth: 420, alignment: .leading)

                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 10) {
                slackStatusSyncRuleTextSourcePicker(index: index)
                    .frame(width: 180, alignment: .leading)

                if draft.slackStatusSyncRules[index].statusTextSource == .fixed {
                    slackStatusSyncRuleTextField(index: index)
                        .frame(minWidth: 260, maxWidth: 520, alignment: .leading)
                }

                slackStatusSyncRuleEmojiField(index: index)
                    .frame(width: 88, alignment: .leading)

                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    func slackStatusSyncRuleIdentity(for rule: SlackStatusSyncRule) -> some View {
        HStack(alignment: .top, spacing: 12) {
            slackWorkspaceBadge(for: rule)

            VStack(alignment: .leading, spacing: 2) {
                Text(slackStatusRuleTitle(for: rule))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(slackStatusRuleSubtitle(for: rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                slackStatusRuleStatusChip(for: rule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func slackStatusSyncRuleConnectionPicker(index: Int) -> some View {
        let rule = draft.slackStatusSyncRules[index]
        let usedPairKeys = slackStatusSyncUsedPairKeys(excludingRuleID: rule.id)

        VStack(alignment: .leading, spacing: 4) {
            Text("Workspace")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker(
                "Slack workspace",
                selection: Binding(
                    get: { draft.slackStatusSyncRules[index].connectionID },
                    set: { updateSlackStatusSyncRuleConnection($0, at: index) }
                )
            ) {
                Text("Choose a workspace").tag("")
                ForEach(slackConnections) { connection in
                    Text(connection.workspaceLabel)
                        .tag(connection.id)
                        .disabled(
                            connection.id != rule.connectionID &&
                                !isSlackStatusSyncPairAvailable(
                                    connectionID: connection.id,
                                    calendarID: rule.calendarID,
                                    usedPairKeys: usedPairKeys
                                )
                        )
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func slackStatusSyncRuleCalendarPicker(index: Int) -> some View {
        let rule = draft.slackStatusSyncRules[index]
        let usedPairKeys = slackStatusSyncUsedPairKeys(excludingRuleID: rule.id)

        VStack(alignment: .leading, spacing: 4) {
            Text("Calendar")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker(
                "Calendar for Slack sync",
                selection: Binding(
                    get: { draft.slackStatusSyncRules[index].calendarID },
                    set: { updateSlackStatusSyncRuleCalendar($0, at: index) }
                )
            ) {
                Text("Choose a calendar").tag("")
                ForEach(availableEventCalendars) { calendar in
                    Text("\(calendar.title) • \(calendar.accountTitle)")
                        .tag(calendar.id)
                        .disabled(
                            calendar.id != rule.calendarID &&
                                !isSlackStatusSyncPairAvailable(
                                    connectionID: rule.connectionID,
                                    calendarID: calendar.id,
                                    usedPairKeys: usedPairKeys
                                )
                        )
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func slackStatusSyncRuleTextSourcePicker(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Status Mode")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker(
                "Slack status mode",
                selection: $draft.slackStatusSyncRules[index].statusTextSource
            ) {
                ForEach(SlackStatusTextSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func slackStatusSyncRuleTextField(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Status Text")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField(
                "In a meeting",
                text: $draft.slackStatusSyncRules[index].statusText
            )
            .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func slackStatusSyncRuleEmojiField(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Emoji")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField(
                "🗓️",
                text: $draft.slackStatusSyncRules[index].statusEmoji
            )
            .textFieldStyle(.roundedBorder)
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

    func slackStatusRuleStatusPreview(for rule: SlackStatusSyncRule) -> String {
        SlackMeetingStatus.statusLine(
            text: rule.statusTextSource == .eventTitle ? "Event Title" : rule.statusText,
            emoji: rule.statusEmoji
        )
    }

    func slackStatusRuleEmojiNeedsPrettyInput(_ rule: SlackStatusSyncRule) -> Bool {
        SlackMeetingStatus.looksLikeSlackAlias(rule.statusEmoji)
    }

    @ViewBuilder
    func slackStatusRuleStatusChip(for rule: SlackStatusSyncRule) -> some View {
        Text(slackStatusRuleStatusPreview(for: rule))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                Capsule(style: .continuous)
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

    @ViewBuilder
    func slackCircularRemoteImage(
        url: URL?,
        fallbackText: String,
        fallbackSymbol: String,
        size: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    slackRemoteImageFallback(
                        text: fallbackText,
                        symbol: fallbackSymbol
                    )
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            slackRemoteImageFallback(
                text: fallbackText,
                symbol: fallbackSymbol
            )
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func slackRemoteImageFallback(text: String, symbol: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))

            if !text.isEmpty {
                Text(text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    func initials(for value: String?) -> String {
        let components = (value ?? "")
            .split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "-" })
            .prefix(2)

        let initials = components.compactMap { component in
            component.first.map { String($0).uppercased() }
        }.joined()

        return initials
    }
}

private struct SlackWorkspaceAvatarPair: View, Equatable {
    let primaryImageURL: URL?
    let secondaryImageURL: URL?
    let primaryInitials: String
    let secondaryInitials: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            remoteImage(
                url: primaryImageURL,
                fallbackText: primaryInitials,
                fallbackSymbol: "person.crop.circle.fill",
                size: 40,
                cornerRadius: 20
            )

            remoteImage(
                url: secondaryImageURL,
                fallbackText: secondaryInitials,
                fallbackSymbol: "building.2.crop.circle.fill",
                size: 20,
                cornerRadius: 10
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
            )
        }
        .frame(width: 44, height: 44)
    }

    @ViewBuilder
    private func remoteImage(
        url: URL?,
        fallbackText: String,
        fallbackSymbol: String,
        size: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    fallbackImage(text: fallbackText, symbol: fallbackSymbol)
                }
            }
            .transaction { transaction in
                transaction.animation = nil
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            fallbackImage(text: fallbackText, symbol: fallbackSymbol)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private func fallbackImage(text: String, symbol: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))

            if !text.isEmpty {
                Text(text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}
