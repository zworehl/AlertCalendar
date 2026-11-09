import SwiftUI

extension SettingsView {
    var generalSettingsPreviewSection: some View {
        settingsSection(
            title: L10n.text("Live Preview"),
            subtitle: L10n.text("One sample surface for the alert state, menu bar label, dropdown list, and contextual previews."),
            systemImage: "rectangle.inset.filled.and.person.filled"
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    generalMenuBarPreview
                        .frame(maxWidth: .infinity, alignment: .leading)
                    generalDropdownPreview
                        .frame(maxWidth: .infinity, alignment: .leading)
                    generalPreviewContextTags
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 14) {
                    generalMenuBarPreview
                    settingsDivider()
                    generalDropdownPreview
                    settingsDivider()
                    generalPreviewContextTags
                }
            }
        }
        .accessibilityIdentifier("settings.general.preview")
    }

    var generalMenuBarPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("Menu Bar"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Circle()
                    .fill(draft.enableBlinkAlert ? Color.red : Color.primary.opacity(0.22))
                    .frame(width: 9, height: 9)
                    .shadow(color: draft.enableBlinkAlert ? Color.red.opacity(0.45) : .clear, radius: 8)

                Text(showcaseMenuBarTitle)
                    .font(.system(size: draft.menuBarFontSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(draft.useSimplifiedCountdown ? L10n.text("2h") : L10n.text("2h 37m"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                showcaseQueueChip("Rotates every \(draft.concurrentEventRotationSeconds)s", isHighlighted: true)
                showcaseQueueChip(draft.activeEventDisplayMode == .remaining ? L10n.text("48m left") : L10n.text("Started 12m ago"))
            }
        }
    }

    var generalDropdownPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("Dropdown"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(showcaseDropdownItems, id: \.self) { item in
                    Text(item)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }

            Text(L10n.text("Window: \(Self.dropdownWindowValueText(hours: draft.lookAheadHours))"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    var generalPreviewContextTags: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("Context"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                showcaseTag("Map")
                showcaseTag(L10n.text("Invitees"))
                showcaseTag("Daylight")
                showcaseTag("Match")
            }

            HStack(spacing: 8) {
                showcaseTimeChip("Alert \(draft.alertLeadMinutes)m before", isHighlighted: draft.enableBlinkAlert)
                showcaseQueueChip("Preview within \(Self.menuBarRotationWindowValueText(minutes: draft.contextualPreviewLeadMinutes))")
            }
        }
    }
}
