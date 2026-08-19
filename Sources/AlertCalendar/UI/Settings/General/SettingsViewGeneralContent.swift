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
                        detail: "Turns near-start items and overdue timed events red so they stand out."
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

            if settingsUsesTwoColumnLayout {
                HStack(alignment: .top, spacing: SettingsVisualMetrics.pageSpacing) {
                    generalMenuBarSettingsSection
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    generalDropdownSettingsSection(maxContextualPreviewLeadMinutes: maxContextualPreviewLeadMinutes)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
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
                    title: "Shorten long titles",
                    detail: "Keeps long event and reminder titles within a compact menu bar limit."
                ) {
                    Toggle("Shorten long titles", isOn: $draft.useEventTitleEllipsis)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel(Text("Shorten long titles"))
                }

                if draft.useEventTitleEllipsis {
                    settingsDivider()

                    settingsControlRow(
                        title: "Maximum characters",
                        detail: "Sets the menu bar title limit before the countdown or status is added."
                    ) {
                        generalSettingStepperControl(valueText: "\(draft.eventTitleMaxCharacters)") {
                            Stepper("", value: eventTitleMaxCharactersBinding, in: 8 ... 80)
                                .labelsHidden()
                        }
                    }

                    settingsDivider()

                    settingsControlRow(
                        title: "Rewrite with Apple Intelligence",
                        detail: appleIntelligenceTitleRewriteIsAllowed
                            ? "Rephrases visible event and reminder titles on device so each compact title stays within the character limit; standard truncation remains the fallback."
                            : "Requires at least 10 characters so the rewritten title still has room to say something useful."
                    ) {
                        Toggle(
                            "Rewrite titles with Apple Intelligence",
                            isOn: eventTitleRewriteBinding
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!agendaSummaryAvailability.isAvailable || !appleIntelligenceTitleRewriteIsAllowed)
                        .accessibilityLabel(Text("Rewrite titles with Apple Intelligence"))
                    }

                    if draft.rewriteEventTitlesWithAppleIntelligence && appleIntelligenceTitleRewriteIsAllowed {
                        settingsDivider()

                        settingsControlRow(
                            title: "Also rewrite dropdown titles",
                            detail: "Uses the same compact replacements in the dropdown list. Leave off to change only the menu bar."
                        ) {
                            Toggle(
                                "Also rewrite dropdown titles",
                                isOn: useRewrittenEventTitlesInDropdownBinding
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityLabel(Text("Also rewrite dropdown titles"))
                        }
                    }

                    if let message = eventTitleRewriteAvailabilityMessage {
                        settingsDivider()

                        Label(message, systemImage: "apple.intelligence")
                            .font(SettingsTypography.supportingText)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                    detail: "Expands from hours to days, weeks, and up to six months as you look further ahead."
                ) {
                    generalSettingStepperControl(
                        valueText: Self.dropdownWindowValueText(hours: draft.lookAheadHours)
                    ) {
                        Stepper {
                            EmptyView()
                        } onIncrement: {
                            draft.lookAheadHours = AppSettingsRules.adjustedDropdownWindowHours(
                                currentValue: draft.lookAheadHours,
                                incrementing: true
                            )
                        } onDecrement: {
                            draft.lookAheadHours = AppSettingsRules.adjustedDropdownWindowHours(
                                currentValue: draft.lookAheadHours,
                                incrementing: false
                            )
                        }
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
                    detail: "Sets the dropdown limit in groups of five, up to 100 rows."
                ) {
                    generalSettingStepperControl(valueText: "\(draft.maxListItems)") {
                        Stepper("", value: $draft.maxListItems, in: 5 ... 100, step: 5)
                            .labelsHidden()
                    }
                }

                settingsDivider()

                settingsControlRow(
                    title: "Agenda summary",
                    detail: "Uses Apple Intelligence on device to generate a concise English overview."
                ) {
                    Toggle("Show agenda summary", isOn: $draft.showAgendaSummary)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel(Text("Show agenda summary"))
                }

                settingsDivider()

                settingsControlRow(
                    title: "Summary length",
                    detail: "Sets the maximum number of words; shorter summaries are still allowed when they cover the visible agenda."
                ) {
                    generalSettingPickerControl {
                        Picker(
                            "Summary length",
                            selection: $draft.agendaSummaryMaximumWords
                        ) {
                            ForEach(AppSettingsRules.agendaSummaryMaximumWordOptions, id: \.self) { wordCount in
                                Text("\(wordCount) words").tag(wordCount)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .disabled(!draft.showAgendaSummary)
                    }
                }

                settingsDivider()

                settingsControlRow(
                    title: "Linked page previews",
                    detail: "Off by default. When enabled, connects directly to up to three public HTTPS pages, which can observe the request. Meeting links, private networks, files, credentials, and sensitive URL parameters stay blocked."
                ) {
                    Toggle(
                        "Use linked page previews in agenda summary",
                        isOn: $draft.useLinkedPagePreviewsInAgendaSummary
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!draft.showAgendaSummary)
                    .accessibilityLabel(Text("Use linked page previews in agenda summary"))
                }

                if let alertMessage = agendaSummaryAvailability.settingsAlertMessage
                    ?? agendaSummaryGenerationErrorDescription {
                    settingsDivider()

                    Label(alertMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(SettingsTypography.supportingText)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Agenda Summary unavailable. \(alertMessage)")
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

            Text("Window: \(Self.dropdownWindowValueText(hours: draft.lookAheadHours))")
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
