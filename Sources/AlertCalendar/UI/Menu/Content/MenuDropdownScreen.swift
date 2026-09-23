import AppKit

/// All rectangles are AppKit desktop coordinates in points, including displays
/// above or to the left of the main display. Never mix these with backing pixels.
struct MenuDropdownScreen: Equatable {
    static let preferredMaximumSize = CGSize(width: 708, height: 800)
    let id: UInt32
    let frame: CGRect
    let visibleFrame: CGRect
    let backingScaleFactor: CGFloat

    @MainActor
    static var connected: [Self] {
        NSScreen.screens.map {
            Self(
                id: ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0,
                frame: $0.frame,
                visibleFrame: $0.visibleFrame,
                backingScaleFactor: $0.backingScaleFactor
            )
        }
    }

    /// Use one point-based layout for all attached displays. A different pointer
    /// position or backing scale must not select a different menu structure.
    static func commonAvailableSize(screens: [Self]) -> CGSize {
        let width = screens.map(\.visibleFrame.width).min() ?? 1440
        let height = screens.map(\.visibleFrame.height).min() ?? 960
        return CGSize(
            width: max(1, min(preferredMaximumSize.width, width - 16)),
            height: max(1, min(preferredMaximumSize.height, height - 16))
        )
    }

    /// Resolve the display from the panel geometry instead of trusting
    /// `NSWindow.screen` while MenuBarExtra is moving and resizing its window.
    /// During that transition AppKit can temporarily report an adjacent display.
    static func visibleFrameForDropdown(
        windowFrame: CGRect,
        screens: [Self]
    ) -> CGRect? {
        screens.max { lhs, rhs in
            dropdownScreenScore(windowFrame: windowFrame, screenFrame: lhs.frame)
                < dropdownScreenScore(windowFrame: windowFrame, screenFrame: rhs.frame)
        }?.visibleFrame
    }

    private static func dropdownScreenScore(
        windowFrame: CGRect,
        screenFrame: CGRect
    ) -> CGFloat {
        let intersection = windowFrame.intersection(screenFrame)
        if !intersection.isNull, !intersection.isEmpty {
            return intersection.width * intersection.height
        }

        let horizontalDistance = max(
            screenFrame.minX - windowFrame.maxX,
            windowFrame.minX - screenFrame.maxX,
            0
        )
        let verticalDistance = max(
            screenFrame.minY - windowFrame.maxY,
            windowFrame.minY - screenFrame.maxY,
            0
        )
        return -(horizontalDistance * horizontalDistance + verticalDistance * verticalDistance)
    }

    /// MenuBarExtra can preserve the bottom edge of its initial maximum-sized
    /// panel when SwiftUI later reports the compact content height. Correct
    /// only conspicuous vertical drift and leave AppKit's normal small gap and
    /// horizontal status-item anchoring intact.
    static func correctedDropdownOrigin(
        windowFrame: CGRect,
        visibleFrame: CGRect,
        preferredTopGap: CGFloat = 4,
        maximumNativeTopGap: CGFloat = 16
    ) -> CGPoint? {
        let topGap = visibleFrame.maxY - windowFrame.maxY
        guard topGap < 0 || topGap > maximumNativeTopGap else { return nil }
        return CGPoint(
            x: windowFrame.minX,
            y: visibleFrame.maxY - preferredTopGap - windowFrame.height
        )
    }
}
