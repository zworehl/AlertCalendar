import AppKit
import SwiftUI

enum MeetingServiceIconProvider {
    @MainActor private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 32
        return cache
    }()

    @MainActor
    static func image(for service: MeetingService, size: CGFloat) -> NSImage? {
        guard let assetName = service.iconAssetName else { return nil }

        let resolvedSize = max(8, size)
        let cacheKey = NSString(string: "\(assetName)|\(resolvedSize)")
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard let assetURL = assetURL(for: assetName),
              let sourceImage = NSImage(contentsOf: assetURL)
        else {
            return nil
        }

        let image = NSImage(size: NSSize(width: resolvedSize, height: resolvedSize))
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill(using: .copy)
        NSGraphicsContext.current?.imageInterpolation = .high
        sourceImage.draw(in: aspectFitRect(for: sourceImage.size, in: NSRect(origin: .zero, size: image.size)))

        image.isTemplate = false
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    private static func assetURL(for assetName: String) -> URL? {
        Bundle.module.url(forResource: assetName, withExtension: "svg")
            ?? Bundle.module.url(
                forResource: assetName,
                withExtension: "svg",
                subdirectory: "Resources/Images/MeetingServices"
            )
    }

    private static func aspectFitRect(for imageSize: CGSize, in rect: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return NSRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

struct MeetingServiceIconView: View {
    let service: MeetingService
    let size: CGFloat
    let fallbackColor: Color
    let isHovered: Bool

    init(
        service: MeetingService,
        size: CGFloat,
        fallbackColor: Color,
        isHovered: Bool = false
    ) {
        self.service = service
        self.size = size
        self.fallbackColor = fallbackColor
        self.isHovered = isHovered
    }

    var body: some View {
        Group {
            if isHovered, let image = MeetingServiceIconProvider.image(for: service, size: size) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "video")
                    .font(.system(size: size, weight: .regular))
                    .foregroundStyle(fallbackColor)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(service.title)
    }
}
