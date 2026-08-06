import AppKit
import SwiftUI

struct SettingsCalendarRowView: View {
    let calendar: AvailableCalendar
    let selectedIDs: Binding<Set<String>>
    let weekdayOnlyIDs: Binding<Set<String>>
    let onSelectionChanged: () -> Void
    let rowHoverBackground: Color
    var calendarAlertRules: Binding<[CalendarAlertRule]>?
    @State private var isHovered = false
    @State private var isShowingAlertRules = false

    var body: some View {
        let isSelected = selectedIDs.wrappedValue.contains(calendar.id)
        let isWeekdayOnly = weekdayOnlyIDs.wrappedValue.contains(calendar.id)

        HStack(spacing: 8) {
            Button {
                setCalendarSelection(isSelected: !isSelected)
            } label: {
                HStack(spacing: 9) {
                    checkSquare(color: Color(nsColor: calendar.color.nsColor), isSelected: isSelected)
                    Text(calendar.title)
                        .font(SettingsTypography.itemTitle)
                        .foregroundStyle(isHovered && isSelected ? Color(nsColor: calendar.color.nsColor) : .primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if calendar.isSubscribed {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary.opacity(0.85))
            }

            if isSelected {
                if calendar.kind == .event, calendarAlertRules != nil {
                    Button {
                        ensureCalendarAlertRule()
                        isShowingAlertRules = true
                    } label: {
                        Image(systemName: alertRule?.isEnabled == true ? "bell.badge.fill" : "bell")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(alertRule?.isEnabled == true ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!calendar.allowsContentModifications)
                    .help(alertRuleHelpText)
                    .popover(isPresented: $isShowingAlertRules, arrowEdge: .trailing) {
                        if calendarAlertRules != nil {
                            SettingsCalendarAlertRuleEditor(
                                calendar: calendar,
                                rule: calendarAlertRuleBinding
                            )
                        }
                    }
                }

                Button {
                    setWeekdayOnly(isWeekdayOnly: !isWeekdayOnly)
                } label: {
                    Text(isWeekdayOnly ? "Weekdays" : "Every day")
                        .font(SettingsTypography.metadataEmphasized)
                        .foregroundStyle(isWeekdayOnly ? .primary : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    isWeekdayOnly
                                        ? Color.accentColor.opacity(0.16)
                                        : Color.secondary.opacity(0.12)
                                )
                        )
                }
                .buttonStyle(.plain)
                .help("Toggle weekdays-only filtering for this calendar")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? rowHoverBackground : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func checkSquare(color: Color, isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color)
            .frame(width: 16, height: 16)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.86))
                }
            }
    }

    private func setCalendarSelection(isSelected: Bool) {
        if isSelected {
            selectedIDs.wrappedValue.insert(calendar.id)
        } else {
            selectedIDs.wrappedValue.remove(calendar.id)
            weekdayOnlyIDs.wrappedValue.remove(calendar.id)
        }
        onSelectionChanged()
    }

    private func setWeekdayOnly(isWeekdayOnly: Bool) {
        if isWeekdayOnly {
            weekdayOnlyIDs.wrappedValue.insert(calendar.id)
        } else {
            weekdayOnlyIDs.wrappedValue.remove(calendar.id)
        }
        onSelectionChanged()
    }

    private var alertRule: CalendarAlertRule? {
        calendarAlertRules?.wrappedValue.first { $0.calendarID == calendar.id }
    }

    private var alertRuleHelpText: String {
        if !calendar.allowsContentModifications {
            return "This calendar is read-only, so its event alerts cannot be changed."
        }
        if alertRule?.isEnabled == true {
            return "Edit this calendar's active alert rule"
        }
        return "Configure alerts for this calendar"
    }

    private var calendarAlertRuleBinding: Binding<CalendarAlertRule> {
        Binding(
            get: {
                alertRule ?? CalendarAlertRule(calendarID: calendar.id)
            },
            set: { updatedRule in
                guard let calendarAlertRules else { return }
                var rules = calendarAlertRules.wrappedValue
                if let index = rules.firstIndex(where: { $0.calendarID == calendar.id }) {
                    rules[index] = updatedRule
                } else {
                    rules.append(updatedRule)
                }
                calendarAlertRules.wrappedValue = rules
            }
        )
    }

    private func ensureCalendarAlertRule() {
        guard let calendarAlertRules, alertRule == nil else { return }
        var rules = calendarAlertRules.wrappedValue
        rules.append(CalendarAlertRule(calendarID: calendar.id))
        calendarAlertRules.wrappedValue = rules
    }
}
