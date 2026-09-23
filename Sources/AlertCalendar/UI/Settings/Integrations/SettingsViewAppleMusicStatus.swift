import SwiftUI

extension SettingsView {
    @ViewBuilder
    var appleMusicStatusRuleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    appleMusicStatusRuleIdentity
                    appleMusicStatusRulePreview
                    Spacer(minLength: 20)
                    appleMusicStatusRuleActions
                        .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        appleMusicStatusRuleIdentity
                        Spacer(minLength: 12)
                        appleMusicStatusRuleActiveToggle
                    }
                    appleMusicStatusRulePreview
                    appleMusicStatusRuleCompactActions
                }
            }

            Divider()
            appleMusicWorkspaceSelection
        }
        .settingsInsetSurface()
    }

    private var appleMusicStatusRuleIdentity: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: draft.appleMusicStatus.source.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(musicSourceTint)
                .frame(width: 32, height: 32)
                .background(musicSourceTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(draft.appleMusicStatus.source.displayName)
                    .font(.subheadline.weight(.semibold))
                Text("Now playing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appleMusicStatusRulePreview: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("While playing")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("🎵 / 🎶  Listening to Artist")
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(SettingsInsetChrome(cornerRadius: 8))
    }

    private var appleMusicStatusRuleActions: some View {
        HStack(alignment: .bottom, spacing: 12) {
            appleMusicStatusRuleSourcePicker
            appleMusicStatusRulePriorityPicker
            appleMusicStatusRuleActiveToggle
        }
    }

    private var appleMusicStatusRuleCompactActions: some View {
        HStack(alignment: .bottom, spacing: 12) {
            appleMusicStatusRuleSourcePicker
                .frame(maxWidth: .infinity, alignment: .leading)
            appleMusicStatusRulePriorityPicker
        }
    }

    private var appleMusicStatusRuleSourcePicker: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Music service")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Music service", selection: $draft.appleMusicStatus.source) {
                ForEach(MusicPlaybackSource.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 170, alignment: .leading)
        }
    }

    private var appleMusicStatusRulePriorityPicker: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Priority")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Priority", selection: $draft.appleMusicStatus.priority) {
                ForEach(SlackStatusPriority.values, id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 64, alignment: .leading)
            .help("1 is highest priority.")
        }
    }

    private var appleMusicStatusRuleActiveToggle: some View {
        Toggle(
            "Active",
            isOn: Binding(
                get: { draft.appleMusicStatus.isEnabled },
                set: { enabled in
                    if enabled, draft.appleMusicStatus.connectionIDs.isEmpty,
                       let firstConnectionID = slackConnections.first?.id {
                        draft.appleMusicStatus.connectionIDs.insert(firstConnectionID)
                    }
                    draft.appleMusicStatus.isEnabled = enabled
                }
            )
        )
        .font(.caption)
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.bottom, 1)
    }

    private var appleMusicWorkspaceSelection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Slack Workspaces")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(slackConnections) { connection in
                Toggle(
                    connection.displayLabel,
                    isOn: Binding(
                        get: { draft.appleMusicStatus.connectionIDs.contains(connection.id) },
                        set: { selected in
                            if selected {
                                draft.appleMusicStatus.connectionIDs.insert(connection.id)
                            } else {
                                draft.appleMusicStatus.connectionIDs.remove(connection.id)
                                if draft.appleMusicStatus.connectionIDs.isEmpty {
                                    draft.appleMusicStatus.isEnabled = false
                                }
                            }
                        }
                    )
                )
                .toggleStyle(.checkbox)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var musicSourceTint: Color {
        draft.appleMusicStatus.source == .appleMusic ? .pink : .red
    }
}
