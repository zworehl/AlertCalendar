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
            if settingsUsesTwoColumnLayout {
                HStack(alignment: .top, spacing: SettingsVisualMetrics.pageSpacing) {
                    generalMenuBarSettingsSection
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: SettingsVisualMetrics.pageSpacing) {
                        generalDropdownSettingsSection(maxContextualPreviewLeadMinutes: maxContextualPreviewLeadMinutes)
                        generalAlertBehaviorSettingsSection
                    }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                VStack(alignment: .leading, spacing: SettingsVisualMetrics.pageSpacing) {
                    generalMenuBarSettingsSection
                    generalDropdownSettingsSection(maxContextualPreviewLeadMinutes: maxContextualPreviewLeadMinutes)
                    generalAlertBehaviorSettingsSection
                }
            }

            languageSettingsSection
            softwareUpdateSettingsSection
            generalSettingsPreviewSection
        }
    }

    var generalAlertBehaviorSettingsSection: some View {
        settingsSection(
            title: L10n.text("Alert Behavior"),
            subtitle: L10n.text("Control when upcoming items become urgent."),
            systemImage: "bell.badge"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                settingsControlRow(
                    title: L10n.text("Blinking alert"),
                    detail: L10n.text("Blinks red during the alert lead time, stopping when an event starts or a reminder becomes due.")
                ) {
                    Toggle(L10n.text("Blinking alert"), isOn: $draft.enableBlinkAlert)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel(Text(L10n.text("Blinking alert")))
                }

                settingsDivider()

                settingsControlRow(
                    title: L10n.text("Alert lead time"),
                    detail: L10n.text("Defines how early the urgent state begins before a meeting starts.")
                ) {
                    generalSettingStepperControl(
                        valueText: Self.durationValueText(
                            value: draft.alertLeadMinutes,
                            singular: L10n.text("minute"),
                            plural: L10n.text("minutes")
                        )
                    ) {
                        Stepper("", value: $draft.alertLeadMinutes, in: 1 ... 60)
                            .labelsHidden()
                    }
                }
            }
        }
    }

    @ViewBuilder
    var generalMenuBarSettingsSection: some View {
        settingsSection(
            title: L10n.text("Menu Bar"),
            subtitle: L10n.text("Tune the compact label that lives in the macOS menu bar."),
            systemImage: "menubar.rectangle"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                settingsControlRow(
                    title: L10n.text("Rotation window"),
                    detail: L10n.text("Only active or near-future items inside this window rotate through the label.")
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
                    title: L10n.text("Focus on active events"),
                    detail: L10n.text("Shows only currently active timed events. If several overlap, the menu bar rotates between those events; otherwise normal rotation continues.")
                ) {
                    Toggle(L10n.text("Focus on active events"), isOn: $draft.focusMenuBarOnActiveEvents)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel(Text(L10n.text("Focus on active events")))
                }

                settingsDivider()

                settingsControlRow(
                    title: L10n.text("Queue rotation"),
                    detail: L10n.text("Controls how quickly concurrent items trade the same menu bar space.")
                ) {
                    generalSettingStepperControl(
                        valueText: Self.durationValueText(
                            value: draft.concurrentEventRotationSeconds,
                            singular: L10n.text("second"),
                            plural: L10n.text("seconds")
                        )
                    ) {
                        Stepper("", value: $draft.concurrentEventRotationSeconds, in: 5 ... 300, step: 5)
                            .labelsHidden()
                    }
                }

                settingsDivider()

                settingsControlRow(
                    title: L10n.text("Font size"),
                    detail: L10n.text("Scales the menu bar label without changing dropdown content.")
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
                    title: L10n.text("Shorten long titles"),
                    detail: L10n.text("Shortens English titles while preserving their purpose. Birthdays use Birthday or Bday as space allows.")
                ) {
                    Toggle(L10n.text("Shorten long titles"), isOn: $draft.useEventTitleEllipsis)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel(Text(L10n.text("Shorten long titles")))
                }

                if draft.useEventTitleEllipsis {
                    settingsDivider()

                    settingsControlRow(
                        title: L10n.text("Maximum characters"),
                        detail: L10n.text("Sets the menu bar title limit before the countdown or status is added.")
                    ) {
                        generalSettingStepperControl(valueText: "\(draft.eventTitleMaxCharacters)") {
                            Stepper("", value: eventTitleMaxCharactersBinding, in: 8 ... 80)
                                .labelsHidden()
                        }
                    }

                    settingsDivider()

                    settingsControlRow(
                        title: L10n.text("Also shorten dropdown titles"),
                        detail: L10n.text("Uses the same abbreviations and character limit in the dropdown list. Leave off to show original titles there.")
                    ) {
                        Toggle(L10n.text("Also shorten dropdown titles"), isOn: useRewrittenEventTitlesInDropdownBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityLabel(Text(L10n.text("Also shorten dropdown titles")))
                    }

                    settingsDivider()

                    settingsControlRow(
                        title: L10n.text("Rewrite with Apple Intelligence"),
                        detail: appleIntelligenceTitleRewriteIsAllowed
                            ? L10n.text("Rephrases English titles on device using event details and relevant attachment context. Local abbreviations work without Apple Intelligence.")
                            : L10n.text("Requires at least 10 characters so the rewritten title still has room to say something useful.")
                    ) {
                        Toggle(
                            L10n.text("Rewrite titles with Apple Intelligence"),
                            isOn: eventTitleRewriteBinding
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!agendaSummaryAvailability.isAvailable || !appleIntelligenceTitleRewriteIsAllowed)
                        .accessibilityLabel(Text(L10n.text("Rewrite titles with Apple Intelligence")))
                    }

                    if draft.rewriteEventTitlesWithAppleIntelligence && appleIntelligenceTitleRewriteIsAllowed {
                        settingsDivider()

                        settingsControlRow(
                            title: L10n.text("Use related Mail context"),
                            detail: L10n.text("Optionally asks Apple Mail for a few messages whose subjects match strong identifiers or the exact event title. Only bounded, redacted context is used on device.")
                        ) {
                            Toggle(
                                L10n.text("Use related Apple Mail messages when rewriting titles"),
                                isOn: $draft.useMailContextForEventTitleRewrite
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityLabel(Text(L10n.text("Use related Mail context")))
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
                    title: L10n.text("Simplified countdown"),
                    detail: L10n.text("Uses a compact one-unit countdown instead of a fuller multi-part value.")
                ) {
                    Toggle(L10n.text("Simplified countdown"), isOn: $draft.useSimplifiedCountdown)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel(Text(L10n.text("Simplified countdown")))
                }

                settingsDivider()

                settingsControlRow(
                    title: L10n.text("Active event timer"),
                    detail: L10n.text("Chooses whether active events read as time left or time already spent.")
                ) {
                    generalSettingPickerControl {
                        Picker(L10n.text("Active event timer"), selection: $draft.activeEventDisplayMode) {
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
            title: L10n.text("Dropdown"),
            subtitle: L10n.text("Shape the list and contextual previews shown when the menu opens."),
            systemImage: "list.bullet.rectangle"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                settingsControlRow(
                    title: L10n.text("Time window"),
                    detail: L10n.text("Expands from hours to days, weeks, and up to six months as you look further ahead.")
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
                    title: L10n.text("Contextual preview lead time"),
                    detail: L10n.text("Maps, attendees, daylight, and football previews activate only near the event.")
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
                    title: L10n.text("Items in list"),
                    detail: L10n.text("Sets the dropdown limit in groups of five, up to 100 rows.")
                ) {
                    generalSettingStepperControl(valueText: "\(draft.maxListItems)") {
                        Stepper("", value: $draft.maxListItems, in: 5 ... 100, step: 5)
                            .labelsHidden()
                    }
                }

                settingsDivider()

                settingsControlRow(
                    title: L10n.text("Agenda summary"),
                    detail: L10n.text("Uses Apple Intelligence on device to summarize the visible schedule, complete notes, and relevant context selected across supported local attachments.")
                ) {
                    Toggle(L10n.text("Show agenda summary"), isOn: $draft.showAgendaSummary)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel(Text(L10n.text("Show agenda summary")))
                }

                settingsDivider()

                settingsControlRow(
                    title: L10n.text("Summary length"),
                    detail: L10n.text("Sets the maximum number of words; shorter summaries are still allowed when they cover the visible agenda.")
                ) {
                    generalSettingPickerControl {
                        Picker(
                            L10n.text("Summary length"),
                            selection: $draft.agendaSummaryMaximumWords
                        ) {
                            ForEach(AppSettingsRules.agendaSummaryMaximumWordOptions, id: \.self) { wordCount in
                                Text(L10n.text("\(wordCount) words")).tag(wordCount)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .disabled(!draft.showAgendaSummary)
                    }
                }

                settingsDivider()

                settingsControlRow(
                    title: L10n.text("Linked page previews"),
                    detail: L10n.text("Off by default. When enabled, connects directly to up to three public HTTPS pages, which can observe the request. Meeting links, private networks, files, credentials, and sensitive URL parameters stay blocked.")
                ) {
                    Toggle(
                        L10n.text("Use linked page previews in agenda summary"),
                        isOn: $draft.useLinkedPagePreviewsInAgendaSummary
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!draft.showAgendaSummary)
                    .accessibilityLabel(Text(L10n.text("Use linked page previews in agenda summary")))
                }

                if let alertMessage = agendaSummaryAvailability.settingsAlertMessage
                    ?? agendaSummaryGenerationErrorDescription {
                    settingsDivider()

                    Label(alertMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(SettingsTypography.supportingText)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(L10n.text("Agenda Summary unavailable. \(alertMessage)"))
                }
            }
        }
    }

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
