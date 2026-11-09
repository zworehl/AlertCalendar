import Foundation

enum MenuDropdownPlacement {
    /// Anchor the panel's top-right edge to the item, then keep it inside the
    /// display's usable frame. Content resizes without moving its top edge.
    static func frame(contentSize: CGSize, buttonFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        let margin: CGFloat = 4
        let width = min(max(1, contentSize.width), max(1, visibleFrame.width - margin * 2))
        let top = min(buttonFrame.minY - margin, visibleFrame.maxY - margin)
        let height = min(max(1, contentSize.height), max(1, top - visibleFrame.minY - margin))
        let left = min(max(buttonFrame.maxX - width, visibleFrame.minX + margin),
                       visibleFrame.maxX - width - margin)
        return CGRect(x: left, y: top - height, width: width, height: height)
    }
}
