import AppKit
import SwiftUI

struct MenuBarStatusLabel: View {
    private static let sharedPillCornerRadius: CGFloat = 2

    let text: String
    let color: NSColor
    let alertedSegmentIndex: Int?
    let alertTextOpacity: CGFloat
    let dotColors: [NSColor]
    let markerStyles: [MenuMarkerStyle]
    let segments: [String]
    let segmentBackgroundColors: [NSColor]
    let segmentBackgroundProgresses: [CGFloat]
    @AppStorage(DefaultsKeys.menuBarFontSize) private var menuBarFontSize = 13.0

    var body: some View {
        Image(
            nsImage: Self.makeBadgeImage(
                text: text,
                color: color,
                alertedSegmentIndex: alertedSegmentIndex,
                alertTextOpacity: alertTextOpacity,
                dotColors: dotColors,
                markerStyles: markerStyles,
                segments: segments,
                segmentBackgroundColors: segmentBackgroundColors,
                segmentBackgroundProgresses: segmentBackgroundProgresses,
                fontSize: CGFloat(menuBarFontSize)
            )
        )
        .renderingMode(.original)
        .accessibilityLabel(text)
    }

    private static func makeBadgeImage(
        text: String,
        color: NSColor,
        alertedSegmentIndex: Int?,
        alertTextOpacity: CGFloat,
        dotColors: [NSColor],
        markerStyles: [MenuMarkerStyle],
        segments: [String],
        segmentBackgroundColors: [NSColor],
        segmentBackgroundProgresses: [CGFloat],
        fontSize: CGFloat
    ) -> NSImage {
        let clampedFontSize = min(max(fontSize, 10), 18)
        let font = NSFont.systemFont(ofSize: clampedFontSize, weight: .semibold)
        let baseTextAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.97),
        ]
        let textSegments = segments.isEmpty ? [text] : segments
        let attributedSegments = textSegments.enumerated().map { index, segment in
            var attributes = baseTextAttributes
            if let alertedSegmentIndex,
               index == alertedSegmentIndex {
                let useRed = alertTextOpacity >= 0.5
                attributes[.foregroundColor] = useRed ? NSColor.systemRed : NSColor.white.withAlphaComponent(0.97)
            }
            return NSAttributedString(string: segment, attributes: attributes)
        }
        let segmentSizes = attributedSegments.map { $0.size() }

        let statusBarHeight = NSStatusBar.system.thickness
        let segmentBackgroundOutsetX: CGFloat = 4
        let segmentBackgroundOutsetY: CGFloat = 3
        let outerCanvasPaddingX: CGFloat = 1
        let outerCanvasPaddingY: CGFloat = 0
        let height: CGFloat = max(statusBarHeight, ceil(clampedFontSize + 5) + (outerCanvasPaddingY * 2))
        let markerHeight: CGFloat = 10
        let markerWidth: CGFloat = 3
        let imageMarkerSize: CGFloat = 11
        let dots = Array(dotColors.prefix(max(1, textSegments.count)))
        let markers = markerStyles.isEmpty ? dots.map { MenuMarkerStyle.color($0) } : markerStyles
        let markerSpacing: CGFloat = 6
        let segmentSpacing: CGFloat = 8
        let leftPadding: CGFloat = segmentBackgroundOutsetX + outerCanvasPaddingX
        let rightPadding: CGFloat = segmentBackgroundOutsetX + outerCanvasPaddingX
        let textWidth = segmentSizes.reduce(CGFloat(0)) { $0 + $1.width }
        let resolvedMarkers = textSegments.indices.map { index in
            index < markers.count ? markers[index] : .color(color)
        }
        let markerWidths = resolvedMarkers.map {
            markerWidthForStyle($0, defaultWidth: markerWidth, imageWidth: imageMarkerSize)
        }
        let markersWidth = markerWidths.reduce(CGFloat(0), +)
        let markerSpacesWidth = CGFloat(textSegments.count) * markerSpacing
        let spacesWidth = CGFloat(max(0, textSegments.count - 1)) * segmentSpacing
        let width = leftPadding + markersWidth + markerSpacesWidth + textWidth + spacesWidth + rightPadding
        let size = NSSize(width: ceil(width), height: height)

        let image = NSImage(size: size)
        image.isTemplate = false

        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high

        var currentX = leftPadding
        for (index, segment) in attributedSegments.enumerated() {
            let segmentSize = segmentSizes[index]
            let marker = resolvedMarkers[index]
            let currentMarkerWidth = markerWidthForStyle(marker, defaultWidth: markerWidth, imageWidth: imageMarkerSize)
            let markerX = currentX
            let textX = markerX + currentMarkerWidth + markerSpacing
            let backgroundColor = index < segmentBackgroundColors.count ? segmentBackgroundColors[index] : .clear
            let backgroundProgress: CGFloat
            if index < segmentBackgroundProgresses.count {
                backgroundProgress = segmentBackgroundProgresses[index]
            } else {
                backgroundProgress = backgroundColor.alphaComponent > 0.01 ? 1.0 : 0.0
            }
            drawSegmentBackground(
                color: backgroundColor,
                progress: backgroundProgress,
                segmentStartX: markerX,
                segmentWidth: currentMarkerWidth + markerSpacing + segmentSize.width,
                segmentHeight: segmentSize.height,
                canvasHeight: height,
                externalInsetX: segmentBackgroundOutsetX,
                externalInsetY: segmentBackgroundOutsetY,
                outerCanvasPaddingY: outerCanvasPaddingY
            )
            drawMarker(
                style: marker,
                x: markerX,
                height: height,
                markerWidth: currentMarkerWidth,
                markerHeight: markerHeight,
                imageMarkerSize: imageMarkerSize
            )
            let textOrigin = NSPoint(
                x: textX,
                y: floor((height - segmentSize.height) / 2)
            )
            segment.draw(at: textOrigin)
            currentX = textX + segmentSize.width

            guard index < attributedSegments.count - 1 else { continue }
            currentX += segmentSpacing
        }

        return image
    }

    private static func drawMarker(style: MenuMarkerStyle, x: CGFloat, height: CGFloat, markerWidth: CGFloat, markerHeight: CGFloat, imageMarkerSize: CGFloat) {
        switch style {
        case .color(let dotColor):
            let rect = NSRect(
                x: x,
                y: floor((height - markerHeight) / 2),
                width: markerWidth,
                height: markerHeight
            )
            let path = NSBezierPath(
                roundedRect: rect,
                xRadius: Self.sharedPillCornerRadius,
                yRadius: Self.sharedPillCornerRadius
            )
            dotColor.setFill()
            path.fill()
        case .reminder(let ringColor):
            drawReminderMarker(color: ringColor, x: x, height: height, markerSize: imageMarkerSize)
        case .birthday(let markerColor):
            drawSymbolMarker(symbolName: "gift.circle.fill", tintColor: markerColor, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .allDay(let markerColor):
            drawSymbolMarker(symbolName: "calendar.circle.fill", tintColor: markerColor, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .sunrise:
            drawAstronomyMarker(moment: .sunrise, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .solarNoon:
            drawAstronomyMarker(moment: .solarNoon, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .sunset:
            drawAstronomyMarker(moment: .sunset, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .solarMidnight:
            drawAstronomyMarker(moment: .solarMidnight, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .drizzle:
            drawWeatherMarker(symbolName: "cloud.drizzle.fill", x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .rain:
            drawWeatherMarker(symbolName: "cloud.rain.fill", x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .thunderstorm:
            drawWeatherMarker(symbolName: "cloud.bolt.rain.fill", x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        }
    }

    private static func markerWidthForStyle(_ style: MenuMarkerStyle, defaultWidth: CGFloat, imageWidth: CGFloat) -> CGFloat {
        switch style {
        case .color:
            return defaultWidth
        case .reminder, .birthday, .allDay, .sunrise, .solarNoon, .sunset, .solarMidnight, .drizzle, .rain, .thunderstorm:
            return imageWidth
        }
    }

    private static func drawSegmentBackground(
        color: NSColor,
        progress: CGFloat,
        segmentStartX: CGFloat,
        segmentWidth: CGFloat,
        segmentHeight: CGFloat,
        canvasHeight: CGFloat,
        externalInsetX: CGFloat,
        externalInsetY: CGFloat,
        outerCanvasPaddingY: CGFloat
    ) {
        guard color.alphaComponent > 0.01 else { return }
        let clampedProgress = min(max(progress, 0), 1)
        guard clampedProgress > 0 else { return }

        let baseHeight = max(2, segmentHeight)
        let maxHeight = max(2, canvasHeight - (outerCanvasPaddingY * 2))
        let backgroundHeight = min(maxHeight, baseHeight + (externalInsetY * 2))
        let backgroundY = floor((canvasHeight - backgroundHeight) / 2)
        let backgroundRect = NSRect(
            x: segmentStartX - externalInsetX,
            y: backgroundY,
            width: segmentWidth + (externalInsetX * 2),
            height: backgroundHeight
        )
        let fillRect = NSRect(
            x: backgroundRect.minX,
            y: backgroundRect.minY,
            width: backgroundRect.width * clampedProgress,
            height: backgroundRect.height
        )

        NSGraphicsContext.saveGraphicsState()
        let cornerRadius = Self.sharedPillCornerRadius
        if clampedProgress < 1 {
            let trackColor = color.withAlphaComponent(max(0.08, color.alphaComponent * 0.45))
            trackColor.setFill()
            NSBezierPath(roundedRect: backgroundRect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }
        NSBezierPath(roundedRect: backgroundRect, xRadius: cornerRadius, yRadius: cornerRadius).addClip()
        color.setFill()
        NSBezierPath(rect: fillRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawAstronomyMarker(moment: AstronomyMoment, x: CGFloat, height: CGFloat, markerWidth: CGFloat, markerHeight: CGFloat) {
        let pointSize = max(markerWidth, markerHeight)

        let rect = NSRect(
            x: x,
            y: floor((height - markerHeight) / 2),
            width: markerWidth,
            height: markerHeight
        )

        if let icon = AstronomyIconProvider.image(for: moment, pointSize: pointSize) {
            icon.draw(in: rect)
        }
    }

    private static func drawWeatherMarker(symbolName: String, x: CGFloat, height: CGFloat, markerWidth: CGFloat, markerHeight: CGFloat) {
        let pointSize = max(markerWidth, markerHeight)
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration.preferringMulticolor())
        let rect = NSRect(
            x: x,
            y: floor((height - markerHeight) / 2),
            width: markerWidth,
            height: markerHeight
        )
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            symbol.isTemplate = false
            symbol.draw(in: rect)
        }
    }

    private static func drawReminderMarker(color: NSColor, x: CGFloat, height: CGFloat, markerSize: CGFloat) {
        let rect = NSRect(
            x: x,
            y: floor((height - markerSize) / 2),
            width: markerSize,
            height: markerSize
        )

        let outerPath = NSBezierPath(ovalIn: rect.insetBy(dx: 0.6, dy: 0.6))
        outerPath.lineWidth = 1.8
        color.setStroke()
        outerPath.stroke()
    }

    private static func drawSymbolMarker(symbolName: String, tintColor: NSColor, x: CGFloat, height: CGFloat, markerWidth: CGFloat, markerHeight: CGFloat) {
        let pointSize = max(markerWidth, markerHeight)
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            return
        }
        symbol.isTemplate = true
        let rect = NSRect(
            x: x,
            y: floor((height - markerHeight) / 2),
            width: markerWidth,
            height: markerHeight
        )
        symbol.draw(in: rect)
        tintColor.setFill()
        rect.fill(using: .sourceAtop)
    }
}
