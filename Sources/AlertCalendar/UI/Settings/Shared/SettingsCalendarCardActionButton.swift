import SwiftUI

enum SettingsCalendarCardAction {
    case add
    case remove
    case open

    var systemImage: String {
        switch self {
        case .add:
            return "plus"
        case .remove:
            return "minus"
        case .open:
            return "calendar"
        }
    }

    var tint: Color {
        switch self {
        case .add:
            return .green
        case .remove:
            return .red
        case .open:
            return .blue
        }
    }

    var helpText: String {
        switch self {
        case .add:
            return "Add this event to Apple Calendar"
        case .remove:
            return "Remove this event from Apple Calendar"
        case .open:
            return "Open this event in Apple Calendar"
        }
    }
}

struct SettingsCalendarCardActionButton: View {
    let calendarAction: SettingsCalendarCardAction
    var isVisible = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: calendarAction.systemImage)
                .font(.system(size: SettingsVisualMetrics.cardActionIconSize, weight: .bold))
                .foregroundStyle(calendarAction.tint)
                .frame(
                    width: SettingsVisualMetrics.cardActionButtonSize,
                    height: SettingsVisualMetrics.cardActionButtonSize
                )
                .background(
                    RoundedRectangle(
                        cornerRadius: SettingsVisualMetrics.cardActionCornerRadius,
                        style: .continuous
                    )
                    .fill(calendarAction.tint.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: SettingsVisualMetrics.cardActionCornerRadius,
                        style: .continuous
                    )
                    .stroke(calendarAction.tint.opacity(0.28), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(calendarAction.helpText)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.94)
        .allowsHitTesting(isVisible)
        .animation(.easeInOut(duration: 0.14), value: isVisible)
    }
}
