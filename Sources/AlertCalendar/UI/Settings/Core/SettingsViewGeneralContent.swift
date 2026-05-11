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

        GroupBox("Alert") {
            LazyVGrid(columns: generalSettingsGridColumns, alignment: .leading, spacing: 12) {
                generalSettingToggleCard(
                    title: "Enable red blinking alert",
                    detail: "Turns upcoming items inside the alert window into a strong red state so they feel urgent before they begin.",
                    isOn: $draft.enableBlinkAlert
                ) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(draft.enableBlinkAlert ? Color.red : Color.white.opacity(0.18))
                            .frame(width: 10, height: 10)
                            .shadow(color: draft.enableBlinkAlert ? Color.red.opacity(0.45) : .clear, radius: 8)

                        Text("Design review in \(draft.alertLeadMinutes)m")
                            .font(.caption.weight(.semibold))

                        Spacer(minLength: 8)

                        Text(draft.enableBlinkAlert ? "Alert on" : "Alert off")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(draft.enableBlinkAlert ? Color.red : .secondary)
                    }
                }

                generalSettingCard(
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
                } showcase: {
                    HStack(spacing: 8) {
                        showcaseTimeChip("8:\(String(format: "%02d", max(0, 60 - draft.alertLeadMinutes)))", isHighlighted: false)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        showcaseTimeChip("Alert", isHighlighted: true)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        showcaseTimeChip("9:00", isHighlighted: false)
                    }
                }

                generalSettingCard(
                    title: "Queue rotation",
                    detail: "Controls how quickly the menu bar rotates when several items are competing for the same space."
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
                } showcase: {
                    HStack(spacing: 6) {
                        showcaseQueueChip("Standup", isHighlighted: true)
                        showcaseQueueChip("Review")
                        showcaseQueueChip("Lunch")
                        Spacer(minLength: 8)
                        Text("Every \(draft.concurrentEventRotationSeconds)s")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        GroupBox("Display") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: generalSettingsGridColumns, alignment: .leading, spacing: 12) {
                    generalSettingCard(
                        title: "Menu bar rotation window",
                        detail: "Only active or near-future items inside this window are allowed to rotate through the menu bar."
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
                    } showcase: {
                        HStack(spacing: 6) {
                            showcaseQueueChip("Now", isHighlighted: true)
                            showcaseQueueChip("In 2h")
                            showcaseQueueChip("In \(max(3, draft.menuBarRotationWindowMinutes / 60 + 1))h")
                        }
                    }

                    generalSettingCard(
                        title: "Dropdown time window",
                        detail: "Expands or tightens how far into the future timed items can appear in the dropdown."
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
                    } showcase: {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(showcaseDropdownWindowItems, id: \.self) { item in
                                Text(item)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    generalSettingCard(
                        title: "Contextual preview lead time",
                        detail: "Maps, attendees, daylight, and football previews only activate for events that are close enough to matter."
                    ) {
                        generalSettingStepperControl(
                            valueText: Self.menuBarRotationWindowValueText(
                                minutes: draft.contextualPreviewLeadMinutes
                            )
                        ) {
                            Stepper("", value: $draft.contextualPreviewLeadMinutes, in: 60 ... maxContextualPreviewLeadMinutes, step: 60)
                                .labelsHidden()
                        }
                    } showcase: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                showcaseTag("Map")
                                showcaseTag("Invitees")
                                showcaseTag("Daylight")
                                showcaseTag("Match")
                            }

                            Text("Preview opens within \(Self.menuBarRotationWindowValueText(minutes: draft.contextualPreviewLeadMinutes)) of the event.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    generalSettingCard(
                        title: "Items in dropdown list",
                        detail: "Caps how many items the dropdown shows before the rest remain hidden off-screen."
                    ) {
                        generalSettingStepperControl(valueText: "\(draft.maxListItems)") {
                            Stepper("", value: $draft.maxListItems, in: 3 ... 20)
                                .labelsHidden()
                        }
                    } showcase: {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(showcaseDropdownItems, id: \.self) { item in
                                Text(item)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }

                            if draft.maxListItems > showcaseDropdownItems.count {
                                Text("+\(draft.maxListItems - showcaseDropdownItems.count) more slots")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    generalMenuBarPresentationCard
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var generalSettingsGridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 280, maximum: .infinity), spacing: 12, alignment: .top),
            count: generalSettingsGridColumnCount
        )
    }

    var generalSettingsGridColumnCount: Int {
        if settingsWindowWidth >= generalSettingsGridThreeColumnThreshold {
            3
        } else if settingsWindowWidth >= generalSettingsGridTwoColumnThreshold {
            2
        } else {
            1
        }
    }

    var generalSettingsGridTwoColumnThreshold: CGFloat {
        1040
    }

    var generalSettingsGridThreeColumnThreshold: CGFloat {
        1460
    }
}
