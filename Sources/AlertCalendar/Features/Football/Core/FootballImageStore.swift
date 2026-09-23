import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

actor FootballImageStore {
    private let fileManager: FileManager
    private let session: URLSession
    private let baseDirectoryURL: URL
    private var failedRequestDates = AlertCalendarLRUCache<String, Date>(capacity: 256)
    private var resolvedFiles = AlertCalendarLRUCache<String, (url: URL, modifiedAt: Date?)>(capacity: 512)
    private var normalizedFilePaths: Set<String> = []
    private var hasEnsuredDirectory = false
    private var lastCleanupDate: Date?
    private static let requestTimeout: TimeInterval = 6
    private static let resourceTimeout: TimeInterval = 12
    private static let failedRequestRetryInterval: TimeInterval = 30 * 60
    private static let cleanupInterval: TimeInterval = 24 * 60 * 60
    private static let cachedImageRetentionInterval: TimeInterval = 90 * 24 * 60 * 60

    init(fileManager: FileManager = .default, session: URLSession? = nil) {
        self.fileManager = fileManager

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = Self.requestTimeout
            configuration.timeoutIntervalForResource = Self.resourceTimeout
            configuration.waitsForConnectivity = false
            configuration.httpMaximumConnectionsPerHost = 8
            self.session = URLSession(configuration: configuration)
        }

        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.baseDirectoryURL = applicationSupportURL
            .appendingPathComponent("AlertCalendar", isDirectory: true)
            .appendingPathComponent("football-images", isDirectory: true)
    }

    func localFileURL(for remoteURL: URL?) async -> URL? {
        guard let remoteURL else { return nil }
        if !hasEnsuredDirectory {
            ensureDirectoryExists(at: baseDirectoryURL)
            hasEnsuredDirectory = true
        }
        let now = Date()
        await ExternalFeedMetrics.shared.recordCheck(source: "football.images", at: now)
        cleanupCachedImagesIfNeeded(now: now)

        let requestKey = remoteURL.absoluteString
        if let cached = resolvedFiles.value(forKey: requestKey) {
            await ExternalFeedMetrics.shared.recordCacheHit(
                source: "football.images",
                dataDate: cached.modifiedAt,
                at: now
            )
            return cached.url
        }

        let fileExtension = normalizedFileExtension(from: remoteURL)
        let fileName = "\(hashed(remoteURL.absoluteString)).\(fileExtension)"
        let destinationURL = baseDirectoryURL.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: destinationURL.path) {
            let modifiedAt = try? destinationURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            await ExternalFeedMetrics.shared.recordCacheHit(
                source: "football.images",
                dataDate: modifiedAt,
                at: now
            )
            if normalizedFilePaths.insert(destinationURL.path).inserted {
                normalizeExistingImageIfNeeded(at: destinationURL, remoteURL: remoteURL)
            }
            resolvedFiles.insert((destinationURL, modifiedAt), forKey: requestKey)
            return destinationURL
        }

        if let failedAt = failedRequestDates.value(forKey: requestKey),
           now.timeIntervalSince(failedAt) < Self.failedRequestRetryInterval {
            await ExternalFeedMetrics.shared.recordCacheHit(source: "football.images.negative")
            return nil
        }

        let requestStartedAt = Date()
        do {
            var request = URLRequest(url: remoteURL)
            request.timeoutInterval = Self.requestTimeout
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                failedRequestDates.insert(now, forKey: requestKey)
                await ExternalFeedMetrics.shared.recordTransportFailure(
                    source: "football.images",
                    duration: Date().timeIntervalSince(requestStartedAt)
                )
                return nil
            }
            await ExternalFeedMetrics.shared.recordNetworkResponse(
                source: "football.images",
                statusCode: http.statusCode,
                responseBytes: data.count,
                duration: Date().timeIntervalSince(requestStartedAt)
            )
            guard (200...299).contains(http.statusCode), !data.isEmpty else {
                failedRequestDates.insert(now, forKey: requestKey)
                return nil
            }

            let imageData = Self.normalizedImageData(from: data, remoteURL: remoteURL)
            try imageData.write(to: destinationURL, options: [.atomic])
            failedRequestDates.removeValue(forKey: requestKey)
            normalizedFilePaths.insert(destinationURL.path)
            resolvedFiles.insert((destinationURL, now), forKey: requestKey)
            return destinationURL
        } catch {
            failedRequestDates.insert(now, forKey: requestKey)
            await ExternalFeedMetrics.shared.recordTransportFailure(
                source: "football.images",
                duration: Date().timeIntervalSince(requestStartedAt)
            )
            return nil
        }
    }

    private func cleanupCachedImagesIfNeeded(now: Date) {
        if let lastCleanupDate,
           now.timeIntervalSince(lastCleanupDate) < Self.cleanupInterval {
            return
        }
        lastCleanupDate = now
        resolvedFiles.removeAll(keepingCapacity: true)
        normalizedFilePaths.removeAll(keepingCapacity: true)
        guard let files = try? fileManager.contentsOfDirectory(
            at: baseDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for fileURL in files {
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modifiedAt = values.contentModificationDate,
                  now.timeIntervalSince(modifiedAt) > Self.cachedImageRetentionInterval else {
                continue
            }
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func ensureDirectoryExists(at url: URL) {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func normalizedFileExtension(from remoteURL: URL) -> String {
        let ext = remoteURL.pathExtension.lowercased()
        return ext.isEmpty ? "png" : ext
    }

    private func normalizeExistingImageIfNeeded(at url: URL, remoteURL: URL) {
        guard Self.shouldNormalizeImage(for: remoteURL),
              let data = try? Data(contentsOf: url) else {
            return
        }

        let imageData = Self.normalizedImageData(from: data, remoteURL: remoteURL)
        guard imageData != data else {
            return
        }

        try? imageData.write(to: url, options: [.atomic])
    }

    nonisolated static func shouldNormalizeImage(for remoteURL: URL) -> Bool {
        shouldRemoveCornerBackground(for: remoteURL)
            || shouldCropTransparentPadding(for: remoteURL)
    }

    nonisolated static func normalizedImageData(from data: Data, remoteURL: URL) -> Data {
        if Self.shouldRemoveCornerBackground(for: remoteURL),
           let imageData = Self.imageDataByRemovingCornerBackground(from: data) {
            return imageData
        }

        if Self.shouldCropTransparentPadding(for: remoteURL),
           let imageData = Self.imageDataByCroppingTransparentPadding(from: data) {
            return imageData
        }

        return data
    }

    nonisolated static func shouldCropTransparentPadding(for remoteURL: URL) -> Bool {
        remoteURL.host?.caseInsensitiveCompare("a.espncdn.com") == .orderedSame
            && remoteURL.path.contains("/i/teamlogos/countries/500/")
    }

    nonisolated static func imageDataByCroppingTransparentPadding(from data: Data) -> Data? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              let cropRect = transparentPaddingCropRect(for: cgImage),
              let croppedImage = cgImage.cropping(to: cropRect) else {
            return nil
        }

        guard cropRect.width < CGFloat(cgImage.width) || cropRect.height < CGFloat(cgImage.height) else {
            return nil
        }

        return pngData(from: croppedImage)
    }

    private nonisolated static func transparentPaddingCropRect(for cgImage: CGImage) -> CGRect? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 1, height > 1 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue

        let didDraw = pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  ) else {
                return false
            }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return nil }

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[((y * width) + x) * bytesPerPixel + 3]
                guard alpha > 16 else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }

    nonisolated static func shouldRemoveCornerBackground(for remoteURL: URL) -> Bool {
        remoteURL.host?.caseInsensitiveCompare("api.fifa.com") == .orderedSame
            && remoteURL.path.contains("/api/v3/picture/associations-sq-2/")
    }

    nonisolated static func imageDataByRemovingCornerBackground(from data: Data) -> Data? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 1, height > 1 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue

        let didDraw = pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  ) else {
                return false
            }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return nil }

        let cornerIndexes = [
            0,
            width - 1,
            (height - 1) * width,
            (height * width) - 1,
        ]
        var removedPixels = [Bool](repeating: false, count: width * height)

        for seedIndex in cornerIndexes {
            removeBackgroundConnectedToSeed(
                seedIndex,
                width: width,
                height: height,
                bytesPerPixel: bytesPerPixel,
                pixels: &pixels,
                removedPixels: &removedPixels
            )
        }

        let removedCount = removedPixels.reduce(0) { $0 + ($1 ? 1 : 0) }
        guard removedCount > 0 else { return nil }

        for index in removedPixels.indices where removedPixels[index] {
            let offset = index * bytesPerPixel
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
            pixels[offset + 3] = 0
        }

        return pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  ),
                  let outputImage = context.makeImage() else {
                return nil
            }

            return pngData(from: outputImage)
        }
    }

    private nonisolated static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private nonisolated static func removeBackgroundConnectedToSeed(
        _ seedIndex: Int,
        width: Int,
        height: Int,
        bytesPerPixel: Int,
        pixels: inout [UInt8],
        removedPixels: inout [Bool]
    ) {
        let seedOffset = seedIndex * bytesPerPixel
        let seedAlpha = pixels[seedOffset + 3]
        guard seedAlpha > 240 else { return }

        let seedColor = (
            red: pixels[seedOffset],
            green: pixels[seedOffset + 1],
            blue: pixels[seedOffset + 2]
        )
        var visited = [Bool](repeating: false, count: width * height)
        var stack = [seedIndex]

        while let index = stack.popLast() {
            guard index >= 0,
                  index < width * height,
                  !visited[index] else {
                continue
            }

            visited[index] = true
            guard pixel(at: index, bytesPerPixel: bytesPerPixel, pixels: pixels, matchesBackground: seedColor) else {
                continue
            }

            removedPixels[index] = true
            let x = index % width
            let y = index / width

            if x > 0 {
                stack.append(index - 1)
            }
            if x + 1 < width {
                stack.append(index + 1)
            }
            if y > 0 {
                stack.append(index - width)
            }
            if y + 1 < height {
                stack.append(index + width)
            }
        }
    }

    private nonisolated static func pixel(
        at index: Int,
        bytesPerPixel: Int,
        pixels: [UInt8],
        matchesBackground seedColor: (red: UInt8, green: UInt8, blue: UInt8)
    ) -> Bool {
        let offset = index * bytesPerPixel
        guard pixels[offset + 3] > 16 else { return false }

        let tolerance = 24
        return abs(Int(pixels[offset]) - Int(seedColor.red)) <= tolerance
            && abs(Int(pixels[offset + 1]) - Int(seedColor.green)) <= tolerance
            && abs(Int(pixels[offset + 2]) - Int(seedColor.blue)) <= tolerance
    }

    private func hashed(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
