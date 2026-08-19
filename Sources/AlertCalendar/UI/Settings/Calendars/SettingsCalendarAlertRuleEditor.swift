import SwiftUI

struct SettingsCalendarAlertRuleEditor: View {
    let calendar: AvailableCalendar
    @Binding var rule: CalendarAlertRule

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    ruleControls

                    Divider()

                    alertSection(
                        title: "Events",
                        detail: "Alerts relative to the event start time.",
                        alerts: $rule.timedEventAlerts,
                        isAllDay: false
                    )

                    Divider()

                    alertSection(
                        title: "All-day events",
                        detail: "Apple-style all-day presets fire at 9:00 AM.",
                        alerts: $rule.allDayEventAlerts,
                        isAllDay: true
                    )
                }
                .padding(.trailing, 4)
            }
            .frame(maxHeight: 560)
        }
        .padding(16)
        .frame(width: 520)
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(nsColor: calendar.color.nsColor))
                .frame(width: 20, height: 20)
                .overlay {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black.opacity(0.78))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(calendar.title)
                    .font(.headline)
                Text("Alert rule · \(calendar.accountTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var ruleControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Apply an alert rule to this calendar", isOn: $rule.isEnabled)
                .toggleStyle(.switch)

            Group {
                SettingsLabeledMenuPicker(
                    title: "Apply to",
                    pickerTitle: "Apply to",
                    selection: $rule.scope,
                    layout: .inline(labelWidth: 72),
                    controlWidth: 170,
                    controlAlignment: .trailing
                ) {
                    ForEach(CalendarAlertRuleScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }

                Toggle("Replace existing event alerts", isOn: $rule.overwriteExistingAlerts)
                    .toggleStyle(.checkbox)

                Text(
                    rule.overwriteExistingAlerts
                        ? "Existing alerts are replaced by the exact series below."
                        : "Configured alerts are added only when they are missing; existing alerts are preserved."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!rule.isEnabled)
        }
    }

    private func alertSection(
        title: String,
        detail: String,
        alerts: Binding<[CalendarEventAlert]>,
        isAllDay: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if alerts.wrappedValue.isEmpty {
                Text(rule.overwriteExistingAlerts ? "No alert — existing alerts will be removed." : "No alerts configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(alerts.wrappedValue) { alert in
                        SettingsCalendarAlertItemEditor(
                            alert: alertBinding(alert.id, in: alerts),
                            isAllDay: isAllDay,
                            onRemove: {
                                alerts.wrappedValue.removeAll { $0.id == alert.id }
                            }
                        )
                    }
                }
            }

            Button {
                alerts.wrappedValue.append(
                    isAllDay ? .allDayOneDayBeforeAtNine : .fifteenMinutesBefore
                )
            } label: {
                Label("Add alert", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(minHeight: SettingsVisualMetrics.minimumInteractiveControlSize)
            .disabled(!rule.isEnabled)
        }
        .disabled(!rule.isEnabled)
    }

    private func alertBinding(
        _ alertID: UUID,
        in alerts: Binding<[CalendarEventAlert]>
    ) -> Binding<CalendarEventAlert> {
        Binding(
            get: {
                alerts.wrappedValue.first { $0.id == alertID } ?? CalendarEventAlert()
            },
            set: { updatedAlert in
                guard let index = alerts.wrappedValue.firstIndex(where: { $0.id == alertID }) else {
                    return
                }
                alerts.wrappedValue[index] = updatedAlert
            }
        )
    }
}

private struct SettingsCalendarAlertItemEditor: View {
    @Binding var alert: CalendarEventAlert
    let isAllDay: Bool
    let onRemove: () -> Void
    @State private var isShowingCustomTiming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                timingMenu

                Button {
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                        .frame(
                            width: SettingsVisualMetrics.minimumInteractiveControlSize,
                            height: SettingsVisualMetrics.minimumInteractiveControlSize
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove alert")
                .help("Remove alert")
            }

            if shouldShowCustomTiming {
                customTimingControls
            }
        }
        .settingsInsetSurface(padding: 10)
    }

    private var timingMenu: some View {
        Menu {
            ForEach(SettingsCalendarAlertPreset.options(isAllDay: isAllDay)) { preset in
                Button(preset.title) {
                    preset.apply(to: &alert)
                    isShowingCustomTiming = false
                }
            }

            Divider()

            Button("Custom…") {
                if alert.timingKind == .timeToLeave {
                    alert.timingKind = .relative
                    alert.relativeOffsetSeconds = isAllDay ? -15 * 60 * 60 : -15 * 60
                }
                isShowingCustomTiming = true
            }
        } label: {
            HStack {
                Text(alert.timingDescription(isAllDay: isAllDay))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 410, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
    }

    private var shouldShowCustomTiming: Bool {
        isShowingCustomTiming || !SettingsCalendarAlertPreset.matchesKnownPreset(alert, isAllDay: isAllDay)
    }

    private var customTimingControls: some View {
        HStack(spacing: 8) {
            TextField("Amount", value: customAmountBinding, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)

            Picker("Unit", selection: customUnitBinding) {
                ForEach(SettingsCalendarAlertUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            .labelsHidden()
            .frame(width: 105)

            Picker("Relation", selection: customRelationBinding) {
                ForEach(SettingsCalendarAlertRelation.allCases) { relation in
                    Text(relation.title).tag(relation)
                }
            }
            .labelsHidden()
            .frame(width: 95)

            Text(isAllDay ? "from midnight" : "event")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var customAmountBinding: Binding<Int> {
        Binding(
            get: {
                max(1, abs(alert.relativeOffsetSeconds) / inferredUnit.seconds)
            },
            set: { newValue in
                setCustomOffset(
                    amount: max(1, min(365, newValue)),
                    unit: inferredUnit,
                    relation: inferredRelation
                )
            }
        )
    }

    private var customUnitBinding: Binding<SettingsCalendarAlertUnit> {
        Binding(
            get: { inferredUnit },
            set: { newUnit in
                setCustomOffset(
                    amount: customAmountBinding.wrappedValue,
                    unit: newUnit,
                    relation: inferredRelation
                )
            }
        )
    }

    private var customRelationBinding: Binding<SettingsCalendarAlertRelation> {
        Binding(
            get: { inferredRelation },
            set: { newRelation in
                setCustomOffset(
                    amount: customAmountBinding.wrappedValue,
                    unit: inferredUnit,
                    relation: newRelation
                )
            }
        )
    }

    private var inferredUnit: SettingsCalendarAlertUnit {
        SettingsCalendarAlertUnit.inferred(from: alert.relativeOffsetSeconds)
    }

    private var inferredRelation: SettingsCalendarAlertRelation {
        alert.relativeOffsetSeconds > 0 ? .after : .before
    }

    private func setCustomOffset(
        amount: Int,
        unit: SettingsCalendarAlertUnit,
        relation: SettingsCalendarAlertRelation
    ) {
        alert.timingKind = .relative
        let seconds = min(
            CalendarEventAlert.maximumAbsoluteOffsetSeconds,
            max(1, amount) * unit.seconds
        )
        alert.relativeOffsetSeconds = relation == .before ? -seconds : seconds
    }
}
