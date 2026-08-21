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

enum MenuListRowPosition {
    case only
    case first
    case middle
    case last

    static func position(for index: Int, itemCount: Int) -> Self {
        guard itemCount > 1 else { return .only }
        if index == 0 { return .first }
        return index == itemCount - 1 ? .last : .middle
    }
}

struct MenuListRowBackgroundShape: Shape {
    let position: MenuListRowPosition
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        guard radius > 0 else {
            var path = Path()
            path.addRect(rect)
            return path
        }

        switch position {
        case .only:
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        case .middle:
            var path = Path()
            path.addRect(rect)
            return path
        case .first:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
            return path
        case .last:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
            path.closeSubpath()
            return path
        }
    }
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
