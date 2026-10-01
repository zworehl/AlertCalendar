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
            appleMusicEmojiSequence
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
                Text(L10n.text("Now playing"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appleMusicStatusRulePreview: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.text("While playing"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(L10n.text("\(draft.appleMusicStatus.emojis.joined(separator: " / "))  Listening to Artist"))
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
            Text(L10n.text("Music service"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker(L10n.text("Music service"), selection: $draft.appleMusicStatus.source) {
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
            Text(L10n.text("Priority"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker(L10n.text("Priority"), selection: $draft.appleMusicStatus.priority) {
                ForEach(SlackStatusPriority.values, id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 64, alignment: .leading)
            .help(L10n.text("1 is highest priority."))
        }
    }

    private var appleMusicStatusRuleActiveToggle: some View {
        Toggle(
            L10n.text("Active"),
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
            Text(L10n.text("Slack Workspaces"))
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

    private var appleMusicEmojiSequence: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L10n.text("Status emoji rotation"))
                    .font(.caption2.weight(.semibold))
                Text("\(draft.appleMusicStatus.emojis.count)/\(AppleMusicStatusSettings.maximumEmojis)")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(Array(draft.appleMusicStatus.emojis.enumerated()), id: \.offset) { index, emoji in
                        VStack(spacing: 2) {
                            HStack(spacing: 3) {
                                Text(emoji)
                                    .font(.title3)
                                    .frame(width: 30, height: 30)
                                    .contentShape(Rectangle())
                                    .help(L10n.text("Drag to reorder"))
                                    .onDrag {
                                        draggingMusicEmojiIndex = index
                                        return NSItemProvider(object: String(index) as NSString)
                                    }

                                Button(role: .destructive) {
                                    draft.appleMusicStatus.emojis.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(draft.appleMusicStatus.emojis.count == 1)
                                .help(L10n.text("Remove emoji"))
                            }

                            Text("\(index + 1)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(5)
                        .background(SettingsInsetChrome(cornerRadius: 8))
                        .opacity(draggingMusicEmojiIndex == index ? 0.55 : 1)
                        .onDrop(
                            of: [.text],
                            delegate: AppleMusicEmojiDropDelegate(
                                targetIndex: index,
                                emojis: $draft.appleMusicStatus.emojis,
                                draggingIndex: $draggingMusicEmojiIndex
                            )
                        )
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 8) {
                TextField(L10n.text("Emoji or :slack_code:"), text: $musicEmojiCandidate)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                    .onSubmit(addMusicEmoji)
                Button(L10n.text("Add emoji"), action: addMusicEmoji)
                    .disabled(draft.appleMusicStatus.emojis.count >= AppleMusicStatusSettings.maximumEmojis ||
                              SlackEmojiCatalog.normalizedEmoji(musicEmojiCandidate) == nil)
                    .controlSize(.small)
            }

            Text(musicEmojiHelpText)
                .font(.caption2)
                .foregroundStyle(musicEmojiCandidate.isEmpty || SlackEmojiCatalog.normalizedEmoji(musicEmojiCandidate) != nil
                                 ? Color.secondary : Color.red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addMusicEmoji() {
        guard draft.appleMusicStatus.emojis.count < AppleMusicStatusSettings.maximumEmojis,
              let emoji = SlackEmojiCatalog.normalizedEmoji(musicEmojiCandidate) else { return }
        draft.appleMusicStatus.emojis.append(emoji)
        musicEmojiCandidate = ""
    }

    private var musicEmojiHelpText: String {
        if draft.appleMusicStatus.emojis.count >= AppleMusicStatusSettings.maximumEmojis {
            return L10n.text("Maximum 10 emoji. Drag an emoji to change its position.")
        }
        if !musicEmojiCandidate.isEmpty && SlackEmojiCatalog.normalizedEmoji(musicEmojiCandidate) == nil {
            return L10n.text("This emoji is not in Slack's standard emoji catalog.")
        }
        return L10n.text("Add a standard Slack emoji or its :code:. Drag to reorder; the sequence changes every 30 seconds.")
    }

    private var musicSourceTint: Color {
        draft.appleMusicStatus.source == .appleMusic ? .pink : .red
    }
}
