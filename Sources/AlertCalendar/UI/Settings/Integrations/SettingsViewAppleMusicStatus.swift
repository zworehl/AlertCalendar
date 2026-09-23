import SwiftUI

extension SettingsView {
    @ViewBuilder
    var appleMusicStatusRuleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    appleMusicStatusRuleIdentity
                    appleMusicStatusRulePreview
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    appleMusicStatusRuleActions
                        .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        appleMusicStatusRuleIdentity
                        Spacer(minLength: 8)
                        appleMusicStatusRuleActions
                    }
                    appleMusicStatusRulePreview
                }
            }

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    appleMusicWorkspaceSelection
                    Spacer(minLength: 12)
                    appleMusicPlaybackBehavior
                        .frame(maxWidth: 420, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 10) {
                    appleMusicWorkspaceSelection
                    appleMusicPlaybackBehavior
                }
            }
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
        HStack(spacing: 10) {
            Picker("Music service", selection: $draft.appleMusicStatus.source) {
                ForEach(MusicPlaybackSource.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 140)

            Picker("Priority", selection: $draft.appleMusicStatus.priority) {
                ForEach(SlackStatusPriority.values, id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 90)
            .help("1 is highest priority.")

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
        }
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

    private var appleMusicPlaybackBehavior: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Playback Behavior")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(musicPlaybackBehaviorDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if draft.appleMusicStatus.source == .youtubeMusic {
                Button("Open YouTube Music") {
                    guard let url = URL(string: "https://music.youtube.com") else { return }
                    AlertCalendarWorkspace.open(url)
                }
                .buttonStyle(.link)
                .controlSize(.small)
            }
        }
    }

    private var musicSourceTint: Color {
        draft.appleMusicStatus.source == .appleMusic ? .pink : .red
    }

    private var musicPlaybackBehaviorDescription: String {
        let sharedBehavior = "Slack shows “until” with a one-minute safety margin beyond the estimated song end. Pausing, stopping, or changing artists is detected within about five seconds; 🎵 and 🎶 alternate every 30 seconds without extra Slack updates between changes."
        switch draft.appleMusicStatus.source {
        case .appleMusic:
            return "\(sharedBehavior) Consecutive queued songs by the same artist extend the estimate when Music exposes their order."
        case .youtubeMusic:
            return "\(sharedBehavior) Keep YouTube Music open in Safari, Chrome, Edge, Brave, or Arc and allow JavaScript from Apple Events in that browser’s developer settings."
        }
    }
}
