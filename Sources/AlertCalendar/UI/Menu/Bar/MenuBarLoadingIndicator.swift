import AppKit
import SwiftUI

struct MenuBarLoadingIndicator: View {
    nonisolated static let iconSize: CGFloat = 18
    nonisolated static let badgeDiameter: CGFloat = 9
    nonisolated static let canvasSize = NSSize(width: 20, height: 18)
    nonisolated static let frameCount = 12
    nonisolated static let frameIntervalNanoseconds: UInt64 = 80_000_000

    @State private var frameIndex = 0

    var body: some View {
        Image(nsImage: Self.frames[frameIndex])
            .renderingMode(.original)
            .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
            .accessibilityLabel("Alert Calendar is loading")
            .help("Alert Calendar is loading")
            .task {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(nanoseconds: Self.frameIntervalNanoseconds)
                    } catch {
                        return
                    }
                    frameIndex = (frameIndex + 1) % Self.frameCount
                }
            }
    }

    @MainActor static let appIcon: NSImage = {
        let resourceURL = Bundle.module.url(forResource: "icon", withExtension: "png")
        return resourceURL.flatMap(NSImage.init(contentsOf:))
            ?? NSApplication.shared.applicationIconImage
    }()

    @MainActor static let frames: [NSImage] = {
        var images: [NSImage] = []
        for frameIndex in 0..<frameCount {
            images.append(makeFrame(frameIndex: frameIndex))
        }
        return images
    }()

    @MainActor private static func makeFrame(frameIndex: Int) -> NSImage {
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        appIcon.draw(
            in: NSRect(x: 0, y: 0, width: iconSize, height: iconSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        makeLoadingBadge(frameIndex: frameIndex).draw(
            in: NSRect(
                x: canvasSize.width - badgeDiameter,
                y: 0,
                width: badgeDiameter,
                height: badgeDiameter
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        image.isTemplate = false
        return image
    }

    @MainActor private static func makeLoadingBadge(frameIndex: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: badgeDiameter, height: badgeDiameter))
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(x: 0, y: 0, width: badgeDiameter, height: badgeDiameter)
        let lineWidth = max(1.25, badgeDiameter * 0.16)
        let ringRect = rect.insetBy(dx: lineWidth, dy: lineWidth)

        let background = NSBezierPath(ovalIn: ringRect)
        background.lineWidth = lineWidth
        NSColor.systemOrange.withAlphaComponent(0.24).setStroke()
        background.stroke()

        let startAngle = CGFloat(frameIndex % frameCount) * (360 / CGFloat(frameCount))
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: NSPoint(x: rect.midX, y: rect.midY),
            radius: ringRect.width / 2,
            startAngle: startAngle,
            endAngle: startAngle + 235
        )
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        NSColor.systemOrange.setStroke()
        arc.stroke()

        image.isTemplate = false
        return image
    }
}
