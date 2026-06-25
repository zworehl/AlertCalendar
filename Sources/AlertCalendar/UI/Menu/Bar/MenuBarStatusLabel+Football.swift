import AppKit
import SwiftUI

extension MenuBarStatusLabel {
    @MainActor
    static func footballHighlightedSegment(
        text: String,
        side: FootballScoreSide?,
        opacity: CGFloat,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: baseAttributes)
        guard let side,
              let range = FootballFixtureFormatter.scoreHighlightRange(in: text, side: side)
        else {
            return attributed
        }

        let baseColor = baseAttributes[.foregroundColor] as? NSColor ?? NSColor.white.withAlphaComponent(0.97)
        let highlightColor = opacity >= 0.5 ? NSColor.systemGreen : baseColor
        attributed.addAttribute(.foregroundColor, value: highlightColor, range: range)
        return attributed
    }

    @MainActor
    static func alertTextColor(opacity: CGFloat, baseColor: NSColor) -> NSColor {
        let fraction = min(max(opacity, 0), 1)
        if fraction <= 0 {
            return baseColor
        }
        if fraction >= 1 {
            return .systemRed
        }

        let base = baseColor.usingColorSpace(.deviceRGB) ?? baseColor
        let alert = NSColor.systemRed.usingColorSpace(.deviceRGB) ?? .systemRed
        return NSColor(
            red: base.redComponent + ((alert.redComponent - base.redComponent) * fraction),
            green: base.greenComponent + ((alert.greenComponent - base.greenComponent) * fraction),
            blue: base.blueComponent + ((alert.blueComponent - base.blueComponent) * fraction),
            alpha: base.alphaComponent + ((alert.alphaComponent - base.alphaComponent) * fraction)
        )
    }

    @MainActor
    static func footballAttributedSegment(
        display: FootballMenuBarDisplay,
        trailingText: String?,
        statusText: String?,
        statusColor: NSColor,
        font: NSFont,
        highlightSide: FootballScoreSide?,
        highlightOpacity: CGFloat,
        alertTextOpacity: CGFloat?,
        baseColor: NSColor
    ) -> NSAttributedString {
        let segment = NSMutableAttributedString()
        let resolvedBaseColor = alertTextOpacity.map {
            alertTextColor(opacity: $0, baseColor: baseColor)
        } ?? baseColor
        let resolvedStatusColor = alertTextOpacity.map {
            alertTextColor(opacity: $0, baseColor: baseColor)
        } ?? statusColor
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: resolvedBaseColor,
        ]
        let secondaryAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: resolvedBaseColor.withAlphaComponent(0.9),
        ]
        let highlightColor = highlightOpacity >= 0.5 ? NSColor.systemGreen : resolvedBaseColor

        func appendText(_ text: String, attributes: [NSAttributedString.Key: Any] = baseAttributes) {
            segment.append(NSAttributedString(string: text, attributes: attributes))
        }

        func appendLogo(path: String?, usesCircularOutline: Bool) {
            guard let attachment = footballLogoAttachment(
                path: path,
                usesCircularOutline: usesCircularOutline,
                font: font,
                borderColor: resolvedBaseColor
            ) else { return }
            segment.append(attachment)
        }

        appendLogo(
            path: display.homeLocalLogoPath,
            usesCircularOutline: display.homeLogoUsesCircularOutline
        )
        appendText(" ")

        if display.showsScore {
            appendText(
                display.homeScore,
                attributes: highlightSide == .home ? [.font: font, .foregroundColor: highlightColor] : baseAttributes
            )
            appendText(" - ")
            appendText(
                display.awayScore,
                attributes: highlightSide == .away ? [.font: font, .foregroundColor: highlightColor] : baseAttributes
            )
            appendText(" ")
        } else {
            appendText("- ")
        }

        appendLogo(
            path: display.awayLocalLogoPath,
            usesCircularOutline: display.awayLogoUsesCircularOutline
        )

        if let trailingText,
           !trailingText.isEmpty {
            appendText(" ")
            appendText(trailingText, attributes: secondaryAttributes)
        }

        if let statusText,
           !statusText.isEmpty {
            appendText(" ")
            appendText(
                statusText,
                attributes: [
                    .font: font,
                    .foregroundColor: resolvedStatusColor,
                ]
            )
        }

        return segment
    }

    @MainActor
    static func footballLogoAttachment(
        path: String?,
        usesCircularOutline: Bool = false,
        font: NSFont,
        borderColor: NSColor? = nil
    ) -> NSAttributedString? {
        let logoSize: CGFloat = 18
        let resolvedBorderColor = borderColor ?? NSColor.labelColor
        let image: NSImage?
        if let path,
           let localImage = FootballLocalImageCache.cachedImage(for: path) {
            let resolvedImage = localImage.copy() as? NSImage ?? localImage
            image = usesCircularOutline
                ? circularFootballLogoImage(resolvedImage, size: logoSize, borderColor: resolvedBorderColor)
                : resolvedImage
        } else {
            image = footballPlaceholderLogoImage(
                size: logoSize,
                usesCircularOutline: usesCircularOutline,
                borderColor: resolvedBorderColor
            )
        }

        guard let image else { return nil }

        image.size = NSSize(width: logoSize, height: logoSize)

        let attachment = NSTextAttachment()
        attachment.image = image
        let verticalOffset = floor((font.capHeight - logoSize) / 2)
        attachment.bounds = NSRect(
            x: 0,
            y: verticalOffset,
            width: logoSize,
            height: logoSize
        )
        return NSAttributedString(attachment: attachment)
    }

    @MainActor
    static func circularFootballLogoImage(_ source: NSImage, size: CGFloat, borderColor: NSColor) -> NSImage {
        let outputSize = NSSize(width: size, height: size)
        let output = NSImage(size: outputSize)
        let rect = NSRect(origin: .zero, size: outputSize)
        let clipPath = NSBezierPath(ovalIn: rect)

        output.lockFocus()
        defer { output.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        footballFlagCircleFillColor.setFill()
        clipPath.fill()

        NSGraphicsContext.saveGraphicsState()
        clipPath.addClip()
        source.draw(
            in: aspectFillRect(for: source.size, in: rect),
            from: NSRect(origin: .zero, size: source.size),
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        drawFootballFlagCircleBorder(in: rect, size: size, borderColor: borderColor)
        return output
    }

    @MainActor
    static func footballPlaceholderLogoImage(
        size: CGFloat,
        usesCircularOutline: Bool,
        borderColor: NSColor? = nil
    ) -> NSImage? {
        guard usesCircularOutline else {
            return NSImage(
                systemSymbolName: "shield.fill",
                accessibilityDescription: nil
            )?.withSymbolConfiguration(.init(pointSize: size - 1, weight: .semibold))
        }

        let outputSize = NSSize(width: size, height: size)
        let output = NSImage(size: outputSize)
        let rect = NSRect(origin: .zero, size: outputSize)
        let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))

        output.lockFocus()
        defer { output.unlockFocus() }

        footballFlagCircleFillColor.setFill()
        circle.fill()
        drawFootballFlagCircleBorder(in: rect, size: size, borderColor: borderColor ?? NSColor.labelColor)

        let symbolSize = size * 0.56
        let symbolRect = NSRect(
            x: floor((size - symbolSize) / 2),
            y: floor((size - symbolSize) / 2),
            width: symbolSize,
            height: symbolSize
        )
        if let symbol = NSImage(
            systemSymbolName: "flag.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: symbolSize, weight: .semibold)) {
            symbol.draw(in: symbolRect)
            footballFlagPlaceholderTintColor.setFill()
            symbolRect.fill(using: .sourceAtop)
        }

        return output
    }

    @MainActor
    static func drawFootballFlagCircleBorder(in rect: CGRect, size: CGFloat, borderColor: NSColor) {
        let borderWidth = footballFlagCircleBorderWidth(for: size)
        let outerPath = NSBezierPath(ovalIn: rect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2))
        outerPath.lineWidth = borderWidth
        borderColor.setStroke()
        outerPath.stroke()

        let innerPath = NSBezierPath(ovalIn: rect.insetBy(dx: borderWidth + 0.35, dy: borderWidth + 0.35))
        innerPath.lineWidth = 0.5
        footballFlagInnerStrokeColor.setStroke()
        innerPath.stroke()
    }

    static func footballFlagCircleBorderWidth(for size: CGFloat) -> CGFloat {
        max(1, size * 0.065)
    }

    private static let footballFlagCircleFillColor = NSColor.white.withAlphaComponent(0.18)
    private static let footballFlagInnerStrokeColor = NSColor.black.withAlphaComponent(0.18)
    private static let footballFlagPlaceholderTintColor = NSColor.white.withAlphaComponent(0.82)

    static func aspectFillRect(for imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              rect.width > 0,
              rect.height > 0 else {
            return rect
        }

        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
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
