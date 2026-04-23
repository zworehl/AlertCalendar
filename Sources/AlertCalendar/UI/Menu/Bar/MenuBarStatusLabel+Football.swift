import AppKit
import SwiftUI

extension MenuBarStatusLabel {
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

        let highlightColor = opacity >= 0.5 ? NSColor.systemGreen : NSColor.white.withAlphaComponent(0.97)
        attributed.addAttribute(.foregroundColor, value: highlightColor, range: range)
        return attributed
    }

    static func footballAttributedSegment(
        display: FootballMenuBarDisplay,
        trailingText: String?,
        statusText: String?,
        statusColor: NSColor,
        font: NSFont,
        highlightSide: FootballScoreSide?,
        highlightOpacity: CGFloat,
        baseColor: NSColor
    ) -> NSAttributedString {
        let segment = NSMutableAttributedString()
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: baseColor,
        ]
        let secondaryAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: baseColor.withAlphaComponent(0.9),
        ]
        let highlightColor = highlightOpacity >= 0.5 ? NSColor.systemGreen : baseColor

        func appendText(_ text: String, attributes: [NSAttributedString.Key: Any] = baseAttributes) {
            segment.append(NSAttributedString(string: text, attributes: attributes))
        }

        func appendLogo(path: String?) {
            guard let attachment = footballLogoAttachment(path: path, font: font) else { return }
            segment.append(attachment)
        }

        appendLogo(path: display.homeLocalLogoPath)
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

        appendLogo(path: display.awayLocalLogoPath)

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
                    .foregroundColor: statusColor,
                ]
            )
        }

        return segment
    }

    static func footballLogoAttachment(path: String?, font: NSFont) -> NSAttributedString? {
        let logoSize: CGFloat = 18
        let image: NSImage?
        if let path,
           let localImage = NSImage(contentsOfFile: path) {
            image = localImage
        } else {
            image = NSImage(
                systemSymbolName: "shield.fill",
                accessibilityDescription: nil
            )?.withSymbolConfiguration(.init(pointSize: logoSize - 1, weight: .semibold))
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
}
