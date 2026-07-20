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
                Text("Use actual emoji like 🐶, 🗓️, or ⏳. Known Slack aliases are auto-converted when possible, but the fields look better with emoji characters.")
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
        if slackShouldUseWideRuleEditors {
            HStack(alignment: .top, spacing: 14) {
                slackStatusSyncRuleDragHandle(for: rule)

                slackStatusSyncRuleIdentity(for: rule)
                    .frame(minWidth: 210, maxWidth: 300, alignment: .leading)

                slackStatusRuleStatusPreviews(for: rule)
                    .layoutPriority(1)

                Spacer(minLength: 12)

                slackStatusSyncRuleWideTimingControls(index: index)
                    .frame(width: 280, alignment: .leading)

                slackStatusSyncRuleActionBar(index: index, rule: rule, isComplete: isComplete)
                    .fixedSize(horizontal: true, vertical: false)
            }
        } else {
            HStack(alignment: .top, spacing: 14) {
                slackStatusSyncRuleDragHandle(for: rule)

                VStack(alignment: .leading, spacing: 5) {
                    slackStatusSyncRuleIdentity(for: rule)
                    slackStatusRuleStatusPreviews(for: rule)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                slackStatusSyncRuleActionBar(index: index, rule: rule, isComplete: isComplete)
                    .fixedSize(horizontal: true, vertical: false)
            }
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

            slackStatusSyncRuleTimingEditor(index: index)
        }
    }

    var slackShouldUseWideRuleEditors: Bool {
        slackStatusRulesAvailableWidth >= slackWideRuleEditorMinimumColumnWidth
    }

    var slackShouldUseInlineRuleEditorRows: Bool {
        slackStatusRulesAvailableWidth >= 760
    }

    var slackStatusRulesAvailableWidth: CGFloat {
        if slackStatusRulesColumnWidth > 0 {
            return slackStatusRulesColumnWidth
        }
        return max(settingsWindowWidth - 68, 0)
    }

    @ViewBuilder
    func slackStatusSyncRuleWideEditors(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Calendar Mapping")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 10) {
                        slackStatusSyncRuleConnectionPicker(index: index)
                            .frame(width: 220, alignment: .leading)

                        slackStatusSyncRuleCalendarPicker(index: index)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(width: 580, alignment: .leading)

                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Active Status")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 10) {
                        slackStatusSyncRuleTextSourcePicker(index: index)
                            .frame(width: 180, alignment: .leading)

                        if draft.slackStatusSyncRules[index].statusTextSource == .fixed {
                            slackStatusSyncRuleTextField(index: index)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Spacer(minLength: 0)
                        }

                        slackStatusSyncRuleEmojiField(index: index)
                            .frame(width: 100, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if draft.slackStatusSyncRules[index].startsBeforeEvent {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Pre-event Status")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    slackStatusSyncRuleWidePreEventEditors(index: index)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func slackStatusSyncRuleWideTimingControls(index: Int) -> some View {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func slackStatusSyncRuleWidePreEventEditors(index: Int) -> some View {
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
            .frame(maxWidth: .infinity, alignment: .leading)

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
            .frame(width: 100, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

}
