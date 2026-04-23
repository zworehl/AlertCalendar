import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    @ViewBuilder
    func generalSettingCardShell<HeaderAccessory: View, Content: View>(
        title: String,
        detail: String,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                headerAccessory()
            }

            content()
        }
        .padding(14)
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
    func generalSettingCard<Control: View, Showcase: View>(
        title: String,
        detail: String,
        @ViewBuilder control: () -> Control,
        @ViewBuilder showcase: () -> Showcase
    ) -> some View {
        generalSettingCardShell(title: title, detail: detail) {
            EmptyView()
        } content: {
            control()

            VStack(alignment: .leading, spacing: 8) {
                Text("Showcase")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                showcase()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                    )
            }
        }
    }

    @ViewBuilder
    func generalSettingControlCard<Control: View>(
        title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        generalSettingCardShell(title: title, detail: detail) {
            EmptyView()
        } content: {
            control()
        }
    }

    @ViewBuilder
    func generalSettingInlineRow<Control: View>(
        title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                control()
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                control()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    func generalSettingToggleCard<Showcase: View>(
        title: String,
        detail: String,
        isOn: Binding<Bool>,
        @ViewBuilder showcase: () -> Showcase
    ) -> some View {
        generalSettingCardShell(title: title, detail: detail) {
            Toggle("Enabled", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(Text(title))
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Showcase")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                showcase()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                    )
            }
        }
    }

    var generalMenuBarPresentationCard: some View {
        generalSettingCardShell(
            title: "Menu bar presentation",
            detail: "Collects the title styling and active timer options that shape how the menu bar reads at a glance."
        ) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                generalSettingInlineRow(
                    title: "Menu bar font size",
                    detail: "Scales the actual menu bar label so the event can feel more subtle or more assertive."
                ) {
                    generalSettingStepperControl(
                        valueText: String(format: "%.1f pt", draft.menuBarFontSize)
                    ) {
                        Stepper("", value: $draft.menuBarFontSize, in: 10 ... 18, step: 0.5)
                            .labelsHidden()
                    }
                }

                Divider()

                generalSettingInlineRow(
                    title: "Use ellipsis for long titles",
                    detail: "Shortens long meeting titles with an ellipsis so the menu bar stays compact."
                ) {
                    Toggle("Enabled", isOn: $draft.useEventTitleEllipsis)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel(Text("Use ellipsis for long titles"))
                }

                Divider()

                generalSettingInlineRow(
                    title: "Title max characters",
                    detail: "Fine-tunes where the menu bar title gets clipped once ellipsis mode is on."
                ) {
                    generalSettingStepperControl(valueText: "\(draft.eventTitleMaxCharacters)") {
                        Stepper("", value: $draft.eventTitleMaxCharacters, in: 8 ... 80)
                            .labelsHidden()
                    }
                    .disabled(!draft.useEventTitleEllipsis)
                    .opacity(draft.useEventTitleEllipsis ? 1 : 0.55)
                }

                Divider()

                generalSettingInlineRow(
                    title: "Simplified countdown",
                    detail: "Switches between compact one-unit countdowns and fuller multi-part countdowns."
                ) {
                    Toggle("Enabled", isOn: $draft.useSimplifiedCountdown)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel(Text("Simplified countdown"))
                }

                Divider()

                generalSettingInlineRow(
                    title: "Active event timer",
                    detail: "Chooses whether active events read like time left or time already spent in the meeting."
                ) {
                    generalSettingPickerControl {
                        Picker("Active event timer", selection: $draft.activeEventDisplayMode) {
                            ForEach(ActiveEventDisplayMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Showcase")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(showcaseMenuBarTitle)
                            .font(.system(size: draft.menuBarFontSize, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text(draft.useEventTitleEllipsis ? "Full title clips at \(draft.eventTitleMaxCharacters) characters before the ellipsis appears." : "Long titles stay fully visible because ellipsis is off.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            showcaseQueueChip(draft.useSimplifiedCountdown ? "Starts in 2h" : "Starts in 2h 37m", isHighlighted: true)
                            showcaseQueueChip(draft.activeEventDisplayMode == .remaining ? "48m left" : "Started 12m ago")
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                    )
                }
            }
        }
    }

    func generalSettingStepperControl<Control: View>(
        valueText: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            control()
            Text(valueText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    func generalSettingPickerControl<Control: View>(
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack {
            Spacer(minLength: 0)
            control()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    func showcaseTimeChip(_ title: String, isHighlighted: Bool) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isHighlighted ? Color.red : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isHighlighted ? Color.red.opacity(0.14) : Color.white.opacity(0.08))
            )
    }

    func showcaseQueueChip(_ title: String, isHighlighted: Bool = false) -> some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(isHighlighted ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isHighlighted ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
            )
    }

    func showcaseTag(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color(red: 0.24, green: 0.59, blue: 0.97))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(red: 0.24, green: 0.59, blue: 0.97).opacity(0.14))
            )
    }

    var showcaseMenuBarTitle: String {
        let fullTitle = "Quarterly planning with product and operations"
        guard draft.useEventTitleEllipsis else { return fullTitle }
        return showcaseTrimmedTitle(fullTitle, maxLength: draft.eventTitleMaxCharacters)
    }

    var showcaseDropdownItems: [String] {
        let samples = [
            "Standup in 15m",
            "Design review in 2h",
            "Lunch in 3h",
            "Retro in 5h",
            "Town hall tomorrow"
        ]
        return Array(samples.prefix(min(max(draft.maxListItems, 1), samples.count)))
    }

    var showcaseDropdownWindowItems: [String] {
        let samples = [
            "Standup in 15m",
            "Design review in 2h",
            "Lunch in 5h",
            "Town hall in \(max(6, draft.lookAheadHours + 3))h"
        ]
        let visibleCount = draft.lookAheadHours < 4 ? 2 : draft.lookAheadHours < 8 ? 3 : 4
        return Array(samples.prefix(visibleCount))
    }

    func showcaseTrimmedTitle(_ title: String, maxLength: Int) -> String {
        let normalizedLength = max(1, maxLength)
        guard title.count > normalizedLength else { return title }
        return String(title.prefix(max(1, normalizedLength - 1))) + "…"
    }
}
