import AppKit
import Foundation
import ImageIO

@MainActor
enum FootballLocalImageCache {
    private static var loadingImages: [String: Task<CGImage?, Never>] = [:]
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 24 * 1_024 * 1_024
        return cache
    }()

    static func cachedImage(for path: String) -> NSImage? {
        cache.object(forKey: path as NSString)
    }

    static func store(_ image: NSImage, for path: String) {
        let cost = max(1, Int(image.size.width * image.size.height * 4))
        cache.setObject(image, forKey: path as NSString, cost: cost)
    }

    static func loadImage(for path: String) async -> NSImage? {
        if let cachedImage = cachedImage(for: path) {
            return cachedImage
        }

        let pending: Task<CGImage?, Never>
        if let existing = loadingImages[path] {
            pending = existing
        } else {
            let task = Task<CGImage?, Never> { @MainActor in
                defer { loadingImages[path] = nil }
                guard let cgImage = await decodedCGImage(for: path) else { return nil }
                let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                store(image, for: path)
                return cgImage
            }
            loadingImages[path] = task
            pending = task
        }
        guard let decoded = await pending.value, !Task.isCancelled else {
            return nil
        }
        if let image = cachedImage(for: path) { return image }
        let image = NSImage(cgImage: decoded, size: NSSize(width: decoded.width, height: decoded.height))
        store(image, for: path)
        return image
    }

    nonisolated static func decodedCGImage(for path: String) async -> CGImage? {
        await Task.detached(priority: .utility) {
            guard let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
                return nil
            }

            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 192,
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary
            return CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options)
        }.value
    }
}
