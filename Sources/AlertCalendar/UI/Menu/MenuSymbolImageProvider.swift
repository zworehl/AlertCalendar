import AppKit

enum MenuSymbolImageProvider {
    @MainActor
    static func tintedSystemSymbol(
        named symbolName: String,
        pointSize: CGFloat,
        weight: NSFont.Weight,
        tintColor: NSColor
    ) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else {
            return nil
        }

        let image = NSImage(size: symbol.size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let bounds = NSRect(origin: .zero, size: symbol.size)
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        symbol.draw(in: bounds)
        tintColor.setFill()
        bounds.fill(using: .sourceAtop)
        image.isTemplate = false
        return image
    }
}
