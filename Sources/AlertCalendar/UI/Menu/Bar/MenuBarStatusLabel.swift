import AppKit
import SwiftUI

struct MenuBarStatusLabel: View {
    static let sharedPillCornerRadius: CGFloat = 2

    private struct BadgeCacheKey: Equatable {
        let state: MenuBarPresentationState
        let fontSize: CGFloat
        let footballLogoRevision: Int
    }

    @MainActor private static var cachedBadgeKey: BadgeCacheKey?
    @MainActor private static var cachedBadgeImage: NSImage?

    let text: String
    let color: NSColor
    let alertedSegmentIndex: Int?
    let alertTextOpacity: CGFloat
    let dotColors: [NSColor]
    let markerStyles: [MenuMarkerStyle]
    let segments: [String]
    let segmentBackgroundColors: [NSColor]
    let segmentBackgroundProgresses: [CGFloat]
    let segmentParticipationStatuses: [EventParticipationStatus?]
    let segmentTextureStatuses: [EventParticipationStatus?]
    let segmentAccessorySymbolNames: [[String]]
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
                segmentParticipationStatuses: segmentParticipationStatuses,
                segmentTextureStatuses: segmentTextureStatuses,
                segmentAccessorySymbolNames: segmentAccessorySymbolNames,
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
        segmentParticipationStatuses: [EventParticipationStatus?],
        segmentTextureStatuses: [EventParticipationStatus?],
        segmentAccessorySymbolNames: [[String]],
        footballDisplay: FootballMenuBarDisplay?,
        footballTrailingText: String?,
        footballStatusText: String?,
        footballStatusColor: NSColor,
        footballGoalHighlightSide: FootballScoreSide?,
        footballGoalHighlightTextOpacity: CGFloat,
        fontSize: CGFloat,
        footballLogoRevision: Int
    ) -> NSImage {
        let state = MenuBarPresentationState(
            label: text,
            color: color,
            alertedSegmentIndex: alertedSegmentIndex,
            alertTextOpacity: alertTextOpacity,
            dotColors: dotColors,
            markerStyles: markerStyles,
            segments: segments,
            segmentBackgroundColors: segmentBackgroundColors,
            segmentBackgroundProgresses: segmentBackgroundProgresses,
            segmentParticipationStatuses: segmentParticipationStatuses,
            segmentTextureStatuses: segmentTextureStatuses,
            segmentAccessorySymbolNames: segmentAccessorySymbolNames,
            footballDisplay: footballDisplay,
            footballTrailingText: footballTrailingText,
            footballStatusText: footballStatusText,
            footballStatusColor: footballStatusColor,
            footballGoalHighlightSide: footballGoalHighlightSide,
            footballGoalHighlightTextOpacity: footballGoalHighlightTextOpacity
        )
        let clampedFontSize = min(max(fontSize, 10), 18)
        let cacheKey = BadgeCacheKey(
            state: state,
            fontSize: clampedFontSize,
            footballLogoRevision: footballLogoRevision
        )
        if cachedBadgeKey == cacheKey, let cachedBadgeImage {
            return cachedBadgeImage
        }

        let font = NSFont.systemFont(ofSize: clampedFontSize, weight: .semibold)
        let defaultTextColor = NSColor.white.withAlphaComponent(0.97)
        let baseTextAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: defaultTextColor,
        ]
        let textSegments = segments.isEmpty ? [text] : segments
        let resolvedSegments = textSegments.enumerated().map { index, segment in
            let isAlertedSegment = alertedSegmentIndex == index
            let alertedTextOpacity = isAlertedSegment ? alertTextOpacity : nil
            let participationStatus = index < segmentParticipationStatuses.count
                ? segmentParticipationStatuses[index]
                : nil
            let baseSegmentTextColor = segmentTextColor(
                baseColor: defaultTextColor,
                participationStatus: participationStatus
            )
            var segmentTextAttributes = baseTextAttributes
            segmentTextAttributes[.foregroundColor] = baseSegmentTextColor
            if let alertedTextOpacity {
                segmentTextAttributes[.foregroundColor] = alertTextColor(
                    opacity: alertedTextOpacity,
                    baseColor: baseSegmentTextColor
                )
            }

            let segmentAccessorySymbols = index < segmentAccessorySymbolNames.count
                ? segmentAccessorySymbolNames[index]
                : []
            let resolvedTextColor = segmentTextAttributes[.foregroundColor] as? NSColor ?? baseSegmentTextColor
            let attributedSegment: NSAttributedString
            if index == 0,
               let footballDisplay {
                attributedSegment = footballAttributedSegment(
                    display: footballDisplay,
                    trailingText: footballTrailingText,
                    statusText: footballStatusText,
                    statusColor: footballStatusColor,
                    font: font,
                    highlightSide: footballGoalHighlightSide,
                    highlightOpacity: footballGoalHighlightTextOpacity,
                    alertTextOpacity: alertedTextOpacity,
                    baseColor: baseSegmentTextColor
                )
            } else {
                let shouldHighlightFootballScore = index == 0
                    && footballGoalHighlightSide != nil
                    && footballGoalHighlightTextOpacity > 0
                let baseAttributedSegment: NSAttributedString
                if shouldHighlightFootballScore {
                    baseAttributedSegment = footballHighlightedSegment(
                        text: segment,
                        side: footballGoalHighlightSide,
                        opacity: footballGoalHighlightTextOpacity,
                        baseAttributes: segmentTextAttributes
                    )
                } else {
                    baseAttributedSegment = NSAttributedString(string: segment, attributes: segmentTextAttributes)
                }

                if index == 0,
                   let footballStatusText,
                   !footballStatusText.isEmpty {
                    let resolvedStatusColor = alertedTextOpacity.map {
                        alertTextColor(opacity: $0, baseColor: baseSegmentTextColor)
                    } ?? footballStatusColor
                    let mutableSegment = NSMutableAttributedString(attributedString: baseAttributedSegment)
                    mutableSegment.append(NSAttributedString(string: " ", attributes: segmentTextAttributes))
                    mutableSegment.append(
                        NSAttributedString(
                            string: footballStatusText,
                            attributes: [
                                .font: font,
                                .foregroundColor: resolvedStatusColor,
                            ]
                        )
                    )
                    attributedSegment = mutableSegment
                } else {
                    attributedSegment = baseAttributedSegment
                }
            }

            return (
                attributedSegment: attributedSegment,
                accessorySymbolNames: segmentAccessorySymbols,
                accessoryTintColor: resolvedTextColor
            )
        }
        let attributedSegments = resolvedSegments.map { $0.attributedSegment }
        let accessorySymbolNamesBySegment = resolvedSegments.map { $0.accessorySymbolNames }
        let accessoryTintColors = resolvedSegments.map { $0.accessoryTintColor }
        let segmentSizes = attributedSegments.map { $0.size() }
        let accessoryWidths = accessorySymbolNamesBySegment.map {
            accessorySymbolsWidth(symbolNames: $0, font: font)
        }

        let statusBarHeight = NSStatusBar.system.thickness
        let segmentBackgroundOutsetX: CGFloat = 4
        let segmentBackgroundOutsetY: CGFloat = 3
        let outerCanvasPaddingX: CGFloat = 1
        let outerCanvasPaddingY: CGFloat = 0
        let height: CGFloat = max(statusBarHeight, ceil(clampedFontSize + 5) + (outerCanvasPaddingY * 2))
        let markerHeight: CGFloat = 10
        let markerWidth: CGFloat = 3
        let imageMarkerSize = MenuMarkerMetrics.symbolSize
        let dots = Array(dotColors.prefix(max(1, textSegments.count)))
        let markers = markerStyles.isEmpty ? dots.map { MenuMarkerStyle.color(AlertCalendarColor(nsColor: $0)) } : markerStyles
        let markerSpacing: CGFloat = 6
        let segmentSpacing: CGFloat = 8
        let textWidth = zip(segmentSizes, accessoryWidths).reduce(CGFloat(0)) { partial, values in
            partial + values.0.width + values.1
        }
        let resolvedMarkers = textSegments.indices.map { index in
            index < markers.count ? markers[index] : .color(AlertCalendarColor(nsColor: color))
        }
        let defaultHorizontalPadding = segmentBackgroundOutsetX + outerCanvasPaddingX
        let leftPadding = outerHorizontalPadding(
            hasBackground: (segmentBackgroundColors.first?.alphaComponent ?? 0) > 0.01,
            defaultPadding: defaultHorizontalPadding
        )
        let rightPadding = outerHorizontalPadding(
            hasBackground: (segmentBackgroundColors.last?.alphaComponent ?? 0) > 0.01,
            defaultPadding: defaultHorizontalPadding
        )
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
            let accessorySymbols = accessorySymbolNamesBySegment[index]
            let accessoryWidth = accessoryWidths[index]
            let accessoryTintColor = accessoryTintColors[index]
            let marker = resolvedMarkers[index]
            let currentMarkerWidth = markerWidthForStyle(marker, defaultWidth: markerWidth, imageWidth: imageMarkerSize)
            let markerX = currentX
            let textX = markerX + currentMarkerWidth + markerSpacing
            let segmentContentWidth = currentMarkerWidth + markerSpacing + segmentSize.width + accessoryWidth
            let backgroundColor = index < segmentBackgroundColors.count ? segmentBackgroundColors[index] : .clear
            let backgroundProgress: CGFloat
            if index < segmentBackgroundProgresses.count {
                backgroundProgress = segmentBackgroundProgresses[index]
            } else {
                backgroundProgress = backgroundColor.alphaComponent > 0.01 ? 1.0 : 0.0
            }
            let textureStatus = index < segmentTextureStatuses.count
                ? segmentTextureStatuses[index]
                : nil
            drawSegmentBackground(
                color: backgroundColor,
                progress: backgroundProgress,
                textureStatus: textureStatus,
                segmentStartX: markerX,
                segmentWidth: segmentContentWidth,
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
            drawAccessorySymbols(
                symbolNames: accessorySymbols,
                font: font,
                tintColor: accessoryTintColor,
                rightX: markerX + segmentContentWidth,
                canvasHeight: height
            )
            currentX = textX + segmentSize.width + accessoryWidth

            guard index < attributedSegments.count - 1 else { continue }
            currentX += segmentSpacing
        }

        cachedBadgeKey = cacheKey
        cachedBadgeImage = image
        return image
    }

    static func segmentTextColor(
        baseColor: NSColor,
        participationStatus: EventParticipationStatus?
    ) -> NSColor {
        guard let participationStatus else { return baseColor }
        return baseColor.withAlphaComponent(
            baseColor.alphaComponent * participationStatus.appleCalendarStyle.textAlpha
        )
    }

    static func accessorySymbolsWidth(
        symbolNames: [String],
        font: NSFont
    ) -> CGFloat {
        guard !symbolNames.isEmpty else { return 0 }

        let symbolSize = accessorySymbolSize(font: font)
        let leadingSpacing: CGFloat = 6
        let symbolSpacing: CGFloat = 3
        return leadingSpacing
            + (CGFloat(symbolNames.count) * symbolSize)
            + (CGFloat(max(0, symbolNames.count - 1)) * symbolSpacing)
    }

    static func drawAccessorySymbols(
        symbolNames: [String],
        font: NSFont,
        tintColor: NSColor,
        rightX: CGFloat,
        canvasHeight: CGFloat
    ) {
        guard !symbolNames.isEmpty else { return }

        let symbolSize = accessorySymbolSize(font: font)
        let leadingSpacing: CGFloat = 6
        let symbolSpacing: CGFloat = 3
        let totalWidth = accessorySymbolsWidth(symbolNames: symbolNames, font: font)
        var currentX = rightX - totalWidth + leadingSpacing
        let symbolY = floor((canvasHeight - symbolSize) / 2)

        for symbolName in symbolNames {
            drawAccessorySymbol(
                symbolName: symbolName,
                tintColor: tintColor,
                rect: NSRect(x: currentX, y: symbolY, width: symbolSize, height: symbolSize)
            )
            currentX += symbolSize + symbolSpacing
        }
    }

    static func accessorySymbolSize(font: NSFont) -> CGFloat {
        ceil(max(9, font.pointSize - 1))
    }

    static func drawAccessorySymbol(
        symbolName: String,
        tintColor: NSColor,
        rect: NSRect
    ) {
        let pointSize = max(rect.width, rect.height)
        guard let symbol = MenuSymbolImageProvider.tintedSystemSymbol(
            named: symbolName,
            pointSize: pointSize,
            weight: .semibold,
            tintColor: tintColor
        ) else {
            return
        }

        let drawingRect = aspectFitRect(for: symbol.size, in: rect)
        symbol.draw(in: drawingRect)
    }
}
