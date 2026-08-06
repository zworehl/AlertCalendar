import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    @ViewBuilder
    var generalSettingsContent: some View {
        let maxContextualPreviewLeadMinutes = AppSettingsRules.maximumContextualPreviewLeadMinutes(
            dropdownWindowHours: draft.lookAheadHours
        )

        VStack(alignment: .leading, spacing: SettingsVisualMetrics.pageSpacing) {
            settingsSection(
                title: "Alert Behavior",
                subtitle: "Control when upcoming items become urgent.",
                systemImage: "bell.badge"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    settingsControlRow(
                        title: "Blinking alert",
                        detail: "Turns near-start items red so they stand out before they begin."
                    ) {
                        Toggle("Blinking alert", isOn: $draft.enableBlinkAlert)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityLabel(Text("Blinking alert"))
                    }

                    settingsDivider()

                    settingsControlRow(
                        title: "Alert lead time",
                        detail: "Defines how early the urgent state begins before a meeting starts."
                    ) {
                        generalSettingStepperControl(
                            valueText: Self.durationValueText(
                                value: draft.alertLeadMinutes,
                                singular: "minute",
                                plural: "minutes"
                            )
                        ) {
                            Stepper("", value: $draft.alertLeadMinutes, in: 1 ... 60)
                                .labelsHidden()
                        }
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: SettingsVisualMetrics.pageSpacing) {
                    generalMenuBarSettingsSection
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    generalDropdownSettingsSection(maxContextualPreviewLeadMinutes: maxContextualPreviewLeadMinutes)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: SettingsVisualMetrics.pageSpacing) {
                    generalMenuBarSettingsSection
                    generalDropdownSettingsSection(maxContextualPreviewLeadMinutes: maxContextualPreviewLeadMinutes)
                }
            }

            generalSettingsPreviewSection
        }
    }

    @ViewBuilder
    var generalMenuBarSettingsSection: some View {
        settingsSection(
            title: "Menu Bar",
            subtitle: "Tune the compact label that lives in the macOS menu bar.",
            systemImage: "menubar.rectangle"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                settingsControlRow(
                    title: "Rotation window",
                    detail: "Only active or near-future items inside this window rotate through the label."
                ) {
                    generalSettingStepperControl(
                        valueText: Self.menuBarRotationWindowValueText(
                            minutes: draft.menuBarRotationWindowMinutes
                        )
                    ) {
                        Stepper {
                            EmptyView()
                        } onIncrement: {
                            draft.menuBarRotationWindowMinutes = AppSettingsRules.adjustedMenuBarRotationWindowMinutes(
                                currentValue: draft.menuBarRotationWindowMinutes,
                                incrementing: true,
                                dropdownWindowHours: draft.lookAheadHours
                            )
                        } onDecrement: {
                            draft.menuBarRotationWindowMinutes = AppSettingsRules.adjustedMenuBarRotationWindowMinutes(
                                currentValue: draft.menuBarRotationWindowMinutes,
                                incrementing: false,
                                dropdownWindowHours: draft.lookAheadHours
                            )
                        }
                        .labelsHidden()
                    }
                }

                settingsDivider()

                settingsControlRow(
                    title: "Queue rotation",
                    detail: "Controls how quickly concurrent items trade the same menu bar space."
                ) {
                    generalSettingStepperControl(
                        valueText: Self.durationValueText(
                            value: draft.concurrentEventRotationSeconds,
                            singular: "second",
                            plural: "seconds"
                        )
                    ) {
                        Stepper("", value: $draft.concurrentEventRotationSeconds, in: 5 ... 300, step: 5)
                            .labelsHidden()
                    }
                }

                settingsDivider()

                settingsControlRow(
                    title: "Font size",
                    detail: "Scales the menu bar label without changing dropdown content."
                ) {
                    generalSettingStepperControl(
                        valueText: String(format: "%.1f pt", draft.menuBarFontSize)
                    ) {
                        Stepper("", value: $draft.menuBarFontSize, in: 10 ... 18, step: 0.5)
                            .labelsHidden()
                    }
                }

                settingsDivider()

                settingsControlRow(
                    title: "Use ellipsis for long titles",
                    detail: "Shortens long event titles so the menu bar stays compact."
                ) {
                    Toggle("Use ellipsis for long titles", isOn: $draft.useEventTitleEllipsis)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel(Text("Use ellipsis for long titles"))
                }

                settingsDivider()

                settingsControlRow(
                    title: "Title max characters",
                    detail: "Fine-tunes where titles clip when ellipsis mode is enabled."
                ) {
                    generalSettingStepperControl(valueText: "\(draft.eventTitleMaxCharacters)") {
                        Stepper("", value: $draft.eventTitleMaxCharacters, in: 8 ... 80)
                            .labelsHidden()
                    }
                    .disabled(!draft.useEventTitleEllipsis)
                    .opacity(draft.useEventTitleEllipsis ? 1 : 0.55)
                }

                settingsDivider()

                settingsControlRow(
                    title: "Simplified countdown",
                    detail: "Uses a compact one-unit countdown instead of a fuller multi-part value."
                ) {
                    Toggle("Simplified countdown", isOn: $draft.useSimplifiedCountdown)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel(Text("Simplified countdown"))
                }

                settingsDivider()

                settingsControlRow(
                    title: "Active event timer",
                    detail: "Chooses whether active events read as time left or time already spent."
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
            }
        }
    }

    @ViewBuilder
    func generalDropdownSettingsSection(maxContextualPreviewLeadMinutes: Int) -> some View {
        settingsSection(
            title: "Dropdown",
            subtitle: "Shape the list and contextual previews shown when the menu opens.",
            systemImage: "list.bullet.rectangle"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                settingsControlRow(
                    title: "Time window",
                    detail: "Expands or tightens how far into the future timed items can appear."
                ) {
                    generalSettingStepperControl(
                        valueText: Self.durationValueText(
                            value: draft.lookAheadHours,
                            singular: "hour",
                            plural: "hours"
                        )
                    ) {
                        Stepper("", value: $draft.lookAheadHours, in: 1 ... 168)
                            .labelsHidden()
                    }
                }

                settingsDivider()

                settingsControlRow(
                    title: "Contextual preview lead time",
                    detail: "Maps, attendees, daylight, and football previews activate only near the event."
                ) {
                    generalSettingStepperControl(
                        valueText: Self.menuBarRotationWindowValueText(
                            minutes: draft.contextualPreviewLeadMinutes
                        )
                    ) {
                        Stepper("", value: $draft.contextualPreviewLeadMinutes, in: 60 ... maxContextualPreviewLeadMinutes, step: 60)
                            .labelsHidden()
                    }
                }

                settingsDivider()

                settingsControlRow(
                    title: "Items in list",
                    detail: "Caps how many dropdown rows are shown before overflow stays hidden."
                ) {
                    generalSettingStepperControl(valueText: "\(draft.maxListItems)") {
                        Stepper("", value: $draft.maxListItems, in: 3 ... 20)
                            .labelsHidden()
                    }
                }
            }
        }
    }

    var generalSettingsPreviewSection: some View {
        settingsSection(
            title: "Live Preview",
            subtitle: "One sample surface for the alert state, menu bar label, dropdown list, and contextual previews.",
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
    }

    var generalMenuBarPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Menu Bar")
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

                Text(draft.useSimplifiedCountdown ? "2h" : "2h 37m")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                showcaseQueueChip("Rotates every \(draft.concurrentEventRotationSeconds)s", isHighlighted: true)
                showcaseQueueChip(draft.activeEventDisplayMode == .remaining ? "48m left" : "Started 12m ago")
            }
        }
    }

    var generalDropdownPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dropdown")
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

            Text("Window: \(Self.durationValueText(value: draft.lookAheadHours, singular: "hour", plural: "hours"))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    var generalPreviewContextTags: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Context")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                showcaseTag("Map")
                showcaseTag("Invitees")
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
