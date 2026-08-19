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
            return "Stage this event to be added when you click Apply"
        case .remove:
            return "Stage this event to be removed when you click Apply"
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
                .font(.system(size: SettingsVisualMetrics.cardActionIconSize, weight: .semibold))
                .frame(
                    width: SettingsVisualMetrics.cardActionButtonSize,
                    height: SettingsVisualMetrics.cardActionButtonSize
                )
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle)
        .controlSize(.small)
        .tint(calendarAction.tint)
        .help(calendarAction.helpText)
        .accessibilityLabel(calendarAction.helpText)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.94)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .animation(.easeInOut(duration: 0.14), value: isVisible)
    }
}
