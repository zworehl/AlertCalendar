import AppKit
import SwiftUI

struct MenuBarStatusLabel: View {
    static let sharedPillCornerRadius: CGFloat = 2

    let text: String
    let color: NSColor
    let alertedSegmentIndex: Int?
    let alertTextOpacity: CGFloat
    let dotColors: [NSColor]
    let markerStyles: [MenuMarkerStyle]
    let segments: [String]
    let segmentBackgroundColors: [NSColor]
    let segmentBackgroundProgresses: [CGFloat]
    let footballDisplay: FootballMenuBarDisplay?
    let footballTrailingText: String?
    let footballStatusText: String?
    let footballStatusColor: NSColor
    let footballGoalHighlightSide: FootballScoreSide?
    let footballGoalHighlightTextOpacity: CGFloat
    @AppStorage(DefaultsKeys.menuBarFontSize) private var menuBarFontSize = 13.0
    @State private var footballLogoRevision = 0

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
                footballDisplay: footballDisplay,
                footballTrailingText: footballTrailingText,
                footballStatusText: footballStatusText,
                footballStatusColor: footballStatusColor,
                footballGoalHighlightSide: footballGoalHighlightSide,
                footballGoalHighlightTextOpacity: footballGoalHighlightTextOpacity,
                fontSize: CGFloat(menuBarFontSize),
                footballLogoRevision: footballLogoRevision
            )
        )
        .renderingMode(.original)
        .accessibilityLabel(text)
        .task(id: footballLogoTaskID) {
            await preloadFootballLogos()
        }
    }

    private var footballLogoPaths: [String] {
        [
            footballDisplay?.homeLocalLogoPath,
            footballDisplay?.awayLocalLogoPath,
        ]
        .compactMap { $0 }
    }

    private var footballLogoTaskID: String {
        footballLogoPaths.joined(separator: "|")
    }

    @MainActor
    private func preloadFootballLogos() async {
        var loadedImage = false

        for path in footballLogoPaths where FootballLocalImageCache.cachedImage(for: path) == nil {
            if await FootballLocalImageCache.loadImage(for: path) != nil {
                loadedImage = true
            }
        }

        if loadedImage {
            footballLogoRevision += 1
        }
    }

    @MainActor
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
        footballDisplay: FootballMenuBarDisplay?,
        footballTrailingText: String?,
        footballStatusText: String?,
        footballStatusColor: NSColor,
        footballGoalHighlightSide: FootballScoreSide?,
        footballGoalHighlightTextOpacity: CGFloat,
        fontSize: CGFloat,
        footballLogoRevision: Int
    ) -> NSImage {
        _ = footballLogoRevision
        let clampedFontSize = min(max(fontSize, 10), 18)
        let font = NSFont.systemFont(ofSize: clampedFontSize, weight: .semibold)
        let defaultTextColor = NSColor.white.withAlphaComponent(0.97)
        let baseTextAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: defaultTextColor,
        ]
        let textSegments = segments.isEmpty ? [text] : segments
        let attributedSegments = textSegments.enumerated().map { index, segment in
            let isAlertedSegment = alertedSegmentIndex == index
            let alertedTextOpacity = isAlertedSegment ? alertTextOpacity : nil
            var segmentTextAttributes = baseTextAttributes
            if let alertedTextOpacity {
                segmentTextAttributes[.foregroundColor] = alertTextColor(
                    opacity: alertedTextOpacity,
                    baseColor: defaultTextColor
                )
            }

            if index == 0,
               let footballDisplay {
                return footballAttributedSegment(
                    display: footballDisplay,
                    trailingText: footballTrailingText,
                    statusText: footballStatusText,
                    statusColor: footballStatusColor,
                    font: font,
                    highlightSide: footballGoalHighlightSide,
                    highlightOpacity: footballGoalHighlightTextOpacity,
                    alertTextOpacity: alertedTextOpacity,
                    baseColor: defaultTextColor
                )
            }

            let shouldHighlightFootballScore = index == 0
                && footballGoalHighlightSide != nil
                && footballGoalHighlightTextOpacity > 0
            if shouldHighlightFootballScore {
                return footballHighlightedSegment(
                    text: segment,
                    side: footballGoalHighlightSide,
                    opacity: footballGoalHighlightTextOpacity,
                    baseAttributes: segmentTextAttributes
                )
            }

            return NSAttributedString(string: segment, attributes: segmentTextAttributes)
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
        let markers = markerStyles.isEmpty ? dots.map { MenuMarkerStyle.color(AlertCalendarColor(nsColor: $0)) } : markerStyles
        let markerSpacing: CGFloat = 6
        let segmentSpacing: CGFloat = 8
        let leftPadding: CGFloat = segmentBackgroundOutsetX + outerCanvasPaddingX
        let rightPadding: CGFloat = segmentBackgroundOutsetX + outerCanvasPaddingX
        let textWidth = segmentSizes.reduce(CGFloat(0)) { $0 + $1.width }
        let resolvedMarkers = textSegments.indices.map { index in
            index < markers.count ? markers[index] : .color(AlertCalendarColor(nsColor: color))
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
}
