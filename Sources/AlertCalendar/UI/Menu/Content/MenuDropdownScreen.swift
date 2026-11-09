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

    /// Resolve the display from desktop geometry. This also supports status
    /// button replicas on displays other than their hosting window's screen.
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

}
