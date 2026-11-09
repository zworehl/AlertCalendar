import AppKit
import SwiftUI

/// One surface owns the menu's appearance. A behind-window visual effect plus
/// the native transient-window shadow can retain different compositing bounds
/// after a display/scale change. Keep the surface local to the SwiftUI content.
enum MenuDropdownAppearance {
    static let cornerRadius: CGFloat = 12

    @MainActor
    static func configure(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.invalidateShadow()
    }
}

struct MenuDropdownSurface: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: MenuDropdownAppearance.cornerRadius,
            style: .continuous
        )
        content
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .modifier(MenuDropdownContainerBackground())
    }
}

private struct MenuDropdownContainerBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            // Clear the SwiftUI window's own backdrop as well as NSWindow's
            // color, so no second material survives outside the rounded surface.
            content.containerBackground(.clear, for: .window)
        } else {
            content
        }
    }
}
