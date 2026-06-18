import AppKit
import SwiftUI

extension MenuBarStatusLabel {
    static func drawMarker(style: MenuMarkerStyle, x: CGFloat, height: CGFloat, markerWidth: CGFloat, markerHeight: CGFloat, imageMarkerSize: CGFloat) {
        switch style {
        case .color(let dotColor):
            let dotColor = dotColor.nsColor
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
            drawReminderMarker(color: ringColor.nsColor, x: x, height: height, markerSize: imageMarkerSize)
        case .birthday(let markerColor):
            drawSymbolMarker(symbolName: "gift.circle.fill", tintColor: markerColor.nsColor, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .allDay(let markerColor):
            drawSymbolMarker(symbolName: "calendar.circle.fill", tintColor: markerColor.nsColor, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .travel(let markerColor):
            drawSymbolMarker(symbolName: "car.fill", tintColor: markerColor.nsColor, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .sunrise:
            drawAstronomyMarker(moment: .sunrise, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .solarNoon:
            drawAstronomyMarker(moment: .solarNoon, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .sunset:
            drawAstronomyMarker(moment: .sunset, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .solarMidnight:
            drawAstronomyMarker(moment: .solarMidnight, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .perihelion:
            drawAstronomyMarker(moment: .perihelion, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .aphelion:
            drawAstronomyMarker(moment: .aphelion, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .marchEquinox:
            drawAstronomyMarker(moment: .marchEquinox, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .juneSolstice:
            drawAstronomyMarker(moment: .juneSolstice, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .septemberEquinox:
            drawAstronomyMarker(moment: .septemberEquinox, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .decemberSolstice:
            drawAstronomyMarker(moment: .decemberSolstice, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .newMoon:
            drawAstronomyMarker(moment: .newMoon, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .waxingCrescent:
            drawAstronomyMarker(moment: .waxingCrescent, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .firstQuarter:
            drawAstronomyMarker(moment: .firstQuarter, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .waxingGibbous:
            drawAstronomyMarker(moment: .waxingGibbous, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .fullMoon:
            drawAstronomyMarker(moment: .fullMoon, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .waningGibbous:
            drawAstronomyMarker(moment: .waningGibbous, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .lastQuarter:
            drawAstronomyMarker(moment: .lastQuarter, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        case .waningCrescent:
            drawAstronomyMarker(moment: .waningCrescent, x: x, height: height, markerWidth: imageMarkerSize, markerHeight: imageMarkerSize)
        }
    }

    static func markerWidthForStyle(_ style: MenuMarkerStyle, defaultWidth: CGFloat, imageWidth: CGFloat) -> CGFloat {
        switch style {
        case .color:
            return defaultWidth
        case .reminder,
            .birthday,
            .allDay,
            .travel,
            .sunrise,
            .solarNoon,
            .sunset,
            .solarMidnight,
            .perihelion,
            .aphelion,
            .marchEquinox,
            .juneSolstice,
            .septemberEquinox,
            .decemberSolstice,
            .newMoon,
            .waxingCrescent,
            .firstQuarter,
            .waxingGibbous,
            .fullMoon,
            .waningGibbous,
            .lastQuarter,
            .waningCrescent:
            return imageWidth
        }
    }

    static func drawSegmentBackground(
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

    static func drawAstronomyMarker(moment: AstronomyMoment, x: CGFloat, height: CGFloat, markerWidth: CGFloat, markerHeight: CGFloat) {
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

    static func drawReminderMarker(color: NSColor, x: CGFloat, height: CGFloat, markerSize: CGFloat) {
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

    static func drawSymbolMarker(symbolName: String, tintColor: NSColor, x: CGFloat, height: CGFloat, markerWidth: CGFloat, markerHeight: CGFloat) {
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
        let drawingRect = aspectFitRect(for: symbol.size, in: rect)
        symbol.draw(in: drawingRect)
        tintColor.setFill()
        drawingRect.fill(using: .sourceAtop)
    }

    static func aspectFitRect(for imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              rect.width > 0,
              rect.height > 0 else {
            return rect
        }

        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: rect.midX - (width / 2),
            y: rect.midY - (height / 2),
            width: width,
            height: height
        )
    }
}
