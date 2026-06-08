import AppKit
import SwiftUI

struct SettingsCalendarRowView: View {
    let calendar: AvailableCalendar
    let selectedIDs: Binding<Set<String>>
    let weekdayOnlyIDs: Binding<Set<String>>
    let onSelectionChanged: () -> Void
    let rowHoverBackground: Color
    @State private var isHovered = false

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
                        .font(.system(size: 14, weight: .medium))
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
                Button {
                    setWeekdayOnly(isWeekdayOnly: !isWeekdayOnly)
                } label: {
                    Text(isWeekdayOnly ? "Weekdays" : "Every day")
                        .font(.system(size: 10, weight: .semibold))
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
}
