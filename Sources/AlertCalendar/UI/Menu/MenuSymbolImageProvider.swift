import AppKit

enum MenuSymbolImageProvider {
    @MainActor private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 128
        return cache
    }()

    @MainActor
    static func tintedSystemSymbol(
        named symbolName: String,
        pointSize: CGFloat,
        weight: NSFont.Weight,
        tintColor: NSColor
    ) -> NSImage? {
        let tint = AlertCalendarColor(nsColor: tintColor)
        let cacheKey = NSString(
            string: "\(symbolName)|\(pointSize)|\(weight.rawValue)|\(tint.red)|\(tint.green)|\(tint.blue)|\(tint.alpha)"
        )
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

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
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }
}
