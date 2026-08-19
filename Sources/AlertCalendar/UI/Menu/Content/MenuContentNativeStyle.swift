import AppKit
import SwiftUI

/// Shared chrome for the menu-bar extra. The values mirror AppKit's regular and
/// small control metrics rather than introducing an app-specific scale.
enum MenuContentNativeMetrics {
    static let toolbarButtonSize: CGFloat = 28
    static let toolbarSymbolSize: CGFloat = 12
    static let sectionCornerRadius: CGFloat = 8
    static let rowCornerRadius: CGFloat = 6
}

/// `MenuBarExtraStyle.window` supplies the native panel behavior. An AppKit
/// popover material keeps its content visually consistent with system extras and
/// automatically follows the window's active state, appearance, contrast and
/// Reduce Transparency preferences.
struct MenuPopoverVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        Self.makeVisualEffectView()
    }

    static func makeVisualEffectView() -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .popover
        nsView.blendingMode = .behindWindow
        nsView.state = .followsWindowActiveState
    }
}

struct MenuToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuToolbarButton(configuration: configuration)
    }

    private struct MenuToolbarButton: View {
        let configuration: Configuration

        @Environment(\.controlActiveState) private var controlActiveState
        @Environment(\.isEnabled) private var isEnabled
        @FocusState private var isFocused: Bool
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: MenuContentNativeMetrics.toolbarSymbolSize, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    isEnabled
                        ? Color(nsColor: .secondaryLabelColor)
                        : Color(nsColor: .tertiaryLabelColor)
                )
                .frame(
                    width: MenuContentNativeMetrics.toolbarButtonSize,
                    height: MenuContentNativeMetrics.toolbarButtonSize
                )
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(backgroundColor)
                }
                .overlay {
                    if isFocused {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
                    }
                }
                .contentShape(Rectangle())
                .focusable()
                .focused($isFocused)
                .onHover { hovering in
                    isHovered = hovering
                }
                .opacity(isEnabled ? 1 : 0.55)
        }

        private var backgroundColor: Color {
            guard isEnabled else { return .clear }
            if configuration.isPressed {
                return Color.primary.opacity(0.14)
            }
            if isHovered {
                return Color.primary.opacity(controlActiveState == .key ? 0.09 : 0.055)
            }
            return .clear
        }
    }
}

extension View {
    func menuRowHoverBackground(isHovered: Bool, cornerRadius: CGFloat = MenuContentNativeMetrics.rowCornerRadius) -> some View {
        background {
            if isHovered {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
            }
        }
    }
}

/// Owns hover state outside the content it rebuilds. Callers are responsible
/// for keeping the returned view's bounds stable between both states.
struct MenuContentHoverContainer<Content: View>: View {
    let content: (Bool) -> Content
    @State private var isHovered = false

    init(@ViewBuilder content: @escaping (Bool) -> Content) {
        self.content = content
    }

    var body: some View {
        content(isHovered)
            .onHover { hovering in
                guard isHovered != hovering else { return }
                isHovered = hovering
            }
    }
}
