import AppKit
import XCTest
@testable import AlertCalendar

@MainActor
final class MenuBarStatusLabelTests: XCTestCase {
    func testAstronomyMenuMarkersUseMonochromeSystemSymbols() throws {
        for moment in AstronomyMoment.allCases {
            let image = try XCTUnwrap(
                AstronomyIconProvider.monochromeImage(
                    for: moment,
                    pointSize: 14,
                    tintColor: .white
                ),
                "Missing monochrome marker for \(moment.rawValue)"
            )

            XCTAssertFalse(image.isTemplate)
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
            XCTAssertTrue(
                try imageHasOnlyWhiteVisiblePixels(image),
                "Marker is not monochrome white for \(moment.rawValue)"
            )
        }
    }

    func testInitialLoadingIndicatorUsesACompactMenuBarSize() {
        XCTAssertEqual(MenuBarLoadingIndicator.size, 16)
        XCTAssertEqual(MenuBarLoadingIndicator.frames.count, MenuBarLoadingIndicator.frameCount)
        XCTAssertTrue(MenuBarLoadingIndicator.frames.allSatisfy { !$0.isTemplate })
        XCTAssertTrue(MenuBarLoadingIndicator.frames.allSatisfy { $0.size == NSSize(width: 16, height: 16) })
    }

    func testInitialLoadingIndicatorTransitionsFromGreenThroughWhite() {
        let green = MenuBarLoadingIndicator.loadingColor(forFrame: 0).usingColorSpace(.sRGB)
        let mixed = MenuBarLoadingIndicator.loadingColor(
            forFrame: MenuBarLoadingIndicator.frameCount / 4
        ).usingColorSpace(.sRGB)
        let white = MenuBarLoadingIndicator.loadingColor(
            forFrame: MenuBarLoadingIndicator.frameCount / 2
        ).usingColorSpace(.sRGB)

        XCTAssertEqual(green?.redComponent ?? 0, 0.20, accuracy: 0.001)
        XCTAssertEqual(green?.greenComponent ?? 0, 0.88, accuracy: 0.001)
        XCTAssertGreaterThan(mixed?.redComponent ?? 0, green?.redComponent ?? 0)
        XCTAssertLessThan(mixed?.redComponent ?? 0, white?.redComponent ?? 0)
        XCTAssertEqual(white?.redComponent ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(white?.greenComponent ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(white?.blueComponent ?? 0, 1, accuracy: 0.001)
    }

    func testFootballLogoIsAvailableImmediatelyFromLocalPath() throws {
        let image = NSImage(size: NSSize(width: 12, height: 8))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 12, height: 8).fill()
        image.unlockFocus()

        let data = try XCTUnwrap(image.tiffRepresentation)
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tiff")
            .path
        try data.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertNotNil(MenuBarStatusLabel.immediatelyAvailableFootballLogo(at: path))
        XCTAssertNotNil(FootballLocalImageCache.cachedImage(for: path))
    }

    func testSymbolMarkerAspectFitPreservesWideSymbolRatio() {
        let rect = CGRect(x: 10, y: 20, width: 12, height: 12)
        let fitted = MenuBarStatusLabel.aspectFitRect(
            for: CGSize(width: 24, height: 12),
            in: rect
        )

        XCTAssertEqual(fitted.width, 12, accuracy: 0.001)
        XCTAssertEqual(fitted.height, 6, accuracy: 0.001)
        XCTAssertEqual(fitted.midX, rect.midX, accuracy: 0.001)
        XCTAssertEqual(fitted.midY, rect.midY, accuracy: 0.001)
    }

    func testFootballLogoAspectFillCoversCircleWithoutDistortion() {
        let rect = CGRect(x: 10, y: 20, width: 18, height: 18)
        let filled = MenuBarStatusLabel.aspectFillRect(
            for: CGSize(width: 36, height: 18),
            in: rect
        )

        XCTAssertEqual(filled.width, 36, accuracy: 0.001)
        XCTAssertEqual(filled.height, 18, accuracy: 0.001)
        XCTAssertEqual(filled.midX, rect.midX, accuracy: 0.001)
        XCTAssertEqual(filled.midY, rect.midY, accuracy: 0.001)
        XCTAssertLessThanOrEqual(filled.minX, rect.minX)
        XCTAssertGreaterThanOrEqual(filled.maxX, rect.maxX)
    }

    func testFootballAttributedSegmentAppliesAlertColorButKeepsGoalHighlight() throws {
        let display = FootballMenuBarDisplay(
            accessibilityText: "USA 2 - 0 POR",
            competitionName: "Friendly",
            competitionStage: nil,
            homeAbbreviation: "USA",
            awayAbbreviation: "POR",
            showsScore: true,
            homeScore: "2",
            awayScore: "0",
            competitionLocalLogoPath: nil,
            homeLocalLogoPath: nil,
            awayLocalLogoPath: nil,
            homeLogoUsesCircularOutline: true,
            awayLogoUsesCircularOutline: true
        )

        let attributed = MenuBarStatusLabel.footballAttributedSegment(
            display: display,
            trailingText: "45'",
            statusText: "LIVE",
            statusColor: .systemGreen,
            font: .systemFont(ofSize: 13, weight: .semibold),
            highlightSide: .home,
            highlightOpacity: 1,
            alertTextOpacity: 1,
            baseColor: NSColor.white.withAlphaComponent(0.97)
        )

        XCTAssertTrue(try textColor(in: attributed, for: "2").isEqual(NSColor.systemGreen))
        XCTAssertTrue(try textColor(in: attributed, for: "0").isEqual(NSColor.systemRed))
        XCTAssertTrue(try textColor(in: attributed, for: "LIVE").isEqual(NSColor.systemRed))
    }

    func testAlertTextColorInterpolatesBetweenBaseColorAndRed() {
        let baseColor = NSColor.white.withAlphaComponent(0.97)

        let base = MenuBarStatusLabel.alertTextColor(opacity: 0, baseColor: baseColor)
        let mixed = MenuBarStatusLabel.alertTextColor(opacity: 0.5, baseColor: baseColor)
        let red = MenuBarStatusLabel.alertTextColor(opacity: 1, baseColor: baseColor)

        XCTAssertTrue(base.isEqual(baseColor))
        XCTAssertFalse(mixed.isEqual(baseColor))
        XCTAssertFalse(mixed.isEqual(NSColor.systemRed))
        XCTAssertTrue(red.isEqual(NSColor.systemRed))
    }

    func testParticipationTextColorDimsPendingButKeepsAcceptedSolid() {
        let baseColor = NSColor.white.withAlphaComponent(0.97)

        let accepted = MenuBarStatusLabel.segmentTextColor(
            baseColor: baseColor,
            participationStatus: .accepted
        )
        let pending = MenuBarStatusLabel.segmentTextColor(
            baseColor: baseColor,
            participationStatus: .pending
        )

        XCTAssertTrue(accepted.isEqual(baseColor))
        XCTAssertLessThan(pending.alphaComponent, accepted.alphaComponent)
    }

    func testAccessorySymbolsReserveTrailingWidthForBothSymbols() {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let oneSymbolWidth = MenuBarStatusLabel.accessorySymbolsWidth(
            symbolNames: ["paperclip"],
            font: font
        )
        let twoSymbolWidth = MenuBarStatusLabel.accessorySymbolsWidth(
            symbolNames: ["paperclip", "repeat"],
            font: font
        )

        XCTAssertGreaterThan(oneSymbolWidth, 0)
        XCTAssertGreaterThan(twoSymbolWidth, oneSymbolWidth)
    }

    func testAccessorySymbolSizeTracksMenuFont() {
        let small = MenuBarStatusLabel.accessorySymbolSize(
            font: NSFont.systemFont(ofSize: 10, weight: .semibold)
        )
        let large = MenuBarStatusLabel.accessorySymbolSize(
            font: NSFont.systemFont(ofSize: 18, weight: .semibold)
        )

        XCTAssertGreaterThan(large, small)
    }

    private func textColor(in attributed: NSAttributedString, for text: String) throws -> NSColor {
        let range = (attributed.string as NSString).range(of: text)
        guard range.location != NSNotFound else {
            XCTFail("Missing text: \(text)")
            return .clear
        }

        return try XCTUnwrap(
            attributed.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
        )
    }

    private func imageHasOnlyWhiteVisiblePixels(_ image: NSImage) throws -> Bool {
        let data = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        var foundVisiblePixel = false

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.01 else {
                    continue
                }
                foundVisiblePixel = true
                guard color.redComponent > 0.99,
                      color.greenComponent > 0.99,
                      color.blueComponent > 0.99 else {
                    return false
                }
            }
        }

        return foundVisiblePixel
    }
}
