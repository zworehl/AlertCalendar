import SwiftUI

extension SettingsView {
    @ViewBuilder
    var nonWorkingDatesSettingsContent: some View {
        settingsSection(
            title: "Non-working Dates",
            subtitle: "Weekday-only calendars skip these dates for visibility and active-event progress.",
            systemImage: "calendar.badge.exclamationmark"
        ) {
            SettingsNonWorkingDatesPickerView(
                nonWorkingDateKeys: $draft.nonWorkingDateKeys
            )
        }
    }
}

struct SettingsNonWorkingDatesPickerView: View {
    @Binding var nonWorkingDateKeys: Set<String>
    var calendar: Calendar = .current

    private var calendarGridDates: [Date] {
        WorkingDayRules.selectableCalendarGridDates(calendar: calendar)
    }

    private var selectableDateKeys: Set<String> {
        Set(WorkingDayRules.selectableDates(calendar: calendar).map { date in
            WorkingDayRules.dateKey(for: date, calendar: calendar)
        })
    }

    private var normalizedSelectedKeys: Set<String> {
        WorkingDayRules.normalizedNonWorkingDateKeys(nonWorkingDateKeys, calendar: calendar)
    }

    private var dateColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 34, maximum: 58), spacing: 6, alignment: .center),
            count: 7
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: dateColumns, alignment: .center, spacing: 6) {
                ForEach(weekdayHeaderTexts, id: \.self) { title in
                    Text(title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(calendarGridDates, id: \.self) { date in
                    dateButton(for: date)
                }
            }
        }
        .onAppear {
            normalizeSelection()
        }
    }

    @ViewBuilder
    private func dateButton(for date: Date) -> some View {
        let key = WorkingDayRules.dateKey(for: date, calendar: calendar)
        let isInSelectableWindow = selectableDateKeys.contains(key)
        let isSelectable = isInSelectableWindow && WorkingDayRules.isWeekday(date, calendar: calendar)
        let isSelected = normalizedSelectedKeys.contains(key)

        Button {
            guard isSelectable else { return }
            toggleDateKey(key)
        } label: {
            Text(dateCellText(for: date))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 34)
                .foregroundStyle(
                    dateForegroundColor(
                        isInSelectableWindow: isInSelectableWindow,
                        isSelectable: isSelectable,
                        isSelected: isSelected
                    )
                )
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            dateBackgroundColor(
                                isInSelectableWindow: isInSelectableWindow,
                                isSelectable: isSelectable,
                                isSelected: isSelected
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    dateBorderColor(
                                        isInSelectableWindow: isInSelectableWindow,
                                        isSelectable: isSelectable,
                                        isSelected: isSelected
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
        .help(dateHelpText(isInSelectableWindow: isInSelectableWindow, isSelectable: isSelectable, isSelected: isSelected))
    }

    private func toggleDateKey(_ key: String) {
        var keys = normalizedSelectedKeys
        if keys.contains(key) {
            keys.remove(key)
        } else {
            keys.insert(key)
        }
        setDateKeys(keys)
    }

    private func setDateKeys(_ keys: Set<String>) {
        let normalized = WorkingDayRules.normalizedNonWorkingDateKeys(keys, calendar: calendar)
        guard normalized != nonWorkingDateKeys else { return }
        nonWorkingDateKeys = normalized
    }

    private func normalizeSelection() {
        let normalized = normalizedSelectedKeys
        if normalized != nonWorkingDateKeys {
            nonWorkingDateKeys = normalized
        }
    }

    private var weekdayHeaderTexts: [String] {
        calendar.veryShortWeekdaySymbols
    }

    private func dateCellText(for date: Date) -> String {
        "\(dayText(for: date)) \(monthText(for: date).lowercased())"
    }

    private func monthText(for date: Date) -> String {
        symbolText(calendar.shortMonthSymbols, component: .month, date: date)
    }

    private func dayText(for date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    private func symbolText(_ symbols: [String], component: Calendar.Component, date: Date) -> String {
        let value = calendar.component(component, from: date)
        let index = max(0, min(value - 1, symbols.count - 1))
        return symbols[index]
    }

    private func dateHelpText(isInSelectableWindow: Bool, isSelectable: Bool, isSelected: Bool) -> String {
        if isSelected {
            return "Remove non-working date"
        }

        if isSelectable {
            return "Mark as non-working"
        }

        return isInSelectableWindow ? "Weekends are already skipped" : "Outside the selectable four-week window"
    }

    private func dateForegroundColor(
        isInSelectableWindow: Bool,
        isSelectable: Bool,
        isSelected: Bool
    ) -> Color {
        if isSelected {
            return Color.accentColor
        }

        if isSelectable {
            return .primary
        }

        return isInSelectableWindow ? .secondary.opacity(0.55) : .secondary.opacity(0.32)
    }

    private func dateBackgroundColor(
        isInSelectableWindow: Bool,
        isSelectable: Bool,
        isSelected: Bool
    ) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.24)
        }

        if isSelectable {
            return Color.primary.opacity(0.06)
        }

        return isInSelectableWindow ? Color.primary.opacity(0.025) : Color.clear
    }

    private func dateBorderColor(
        isInSelectableWindow: Bool,
        isSelectable: Bool,
        isSelected: Bool
    ) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.78)
        }

        if isSelectable {
            return Color.primary.opacity(0.08)
        }

        return isInSelectableWindow ? Color.primary.opacity(0.035) : Color.clear
    }
}
