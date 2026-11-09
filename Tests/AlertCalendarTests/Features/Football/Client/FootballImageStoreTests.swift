import AppKit
import XCTest
@testable import AlertCalendar

final class FootballImageStoreTests: XCTestCase {
    func testShouldRemoveCornerBackgroundOnlyForFIFAAssociationImages() throws {
        let federationURL = try XCTUnwrap(URL(string: "https://api.fifa.com/api/v3/picture/associations-sq-2/CRC"))
        let espnURL = try XCTUnwrap(URL(string: "https://a.espncdn.com/i/teamlogos/countries/500/crc.png"))

        XCTAssertTrue(FootballImageStore.shouldRemoveCornerBackground(for: federationURL))
        XCTAssertFalse(FootballImageStore.shouldRemoveCornerBackground(for: espnURL))
    }

    func testShouldCropTransparentPaddingOnlyForESPNCountryFlags() throws {
        let countryFlagURL = try XCTUnwrap(URL(string: "https://a.espncdn.com/i/teamlogos/countries/500/crc.png"))
        let clubLogoURL = try XCTUnwrap(URL(string: "https://a.espncdn.com/i/teamlogos/soccer/500/83.png"))

        XCTAssertTrue(FootballImageStore.shouldCropTransparentPadding(for: countryFlagURL))
        XCTAssertFalse(FootballImageStore.shouldCropTransparentPadding(for: clubLogoURL))
    }

    func testImageDataByCroppingTransparentPaddingPreservesFlagAspectRatioContent() throws {
        let data = try pngData(width: 10, height: 10) { x, y in
            if (2...7).contains(x), (1...4).contains(y) {
                return Self.red
            }
            return Self.clear
        }

        let croppedData = try XCTUnwrap(
            FootballImageStore.imageDataByCroppingTransparentPadding(from: data)
        )
        let rep = try XCTUnwrap(NSBitmapImageRep(data: croppedData))

        XCTAssertEqual(rep.pixelsWide, 6)
        XCTAssertEqual(rep.pixelsHigh, 4)
        XCTAssertGreaterThan(try alpha(in: rep, x: 0, y: 0), 0.98)
        XCTAssertGreaterThan(try alpha(in: rep, x: 5, y: 3), 0.98)
    }

    func testImageDataByRemovingCornerBackgroundKeepsInternalWhiteDetails() throws {
        let data = try pngData(width: 8, height: 8) { x, y in
            if x == 4, y == 4 {
                return Self.white
            }
            if (2...5).contains(x), (2...5).contains(y) {
                return Self.red
            }
            return Self.white
        }

        let normalizedData = try XCTUnwrap(
            FootballImageStore.imageDataByRemovingCornerBackground(from: data)
        )
        let rep = try XCTUnwrap(NSBitmapImageRep(data: normalizedData))

        XCTAssertLessThan(try alpha(in: rep, x: 0, y: 0), 0.02)
        XCTAssertGreaterThan(try alpha(in: rep, x: 3, y: 3), 0.98)
        XCTAssertGreaterThan(try alpha(in: rep, x: 4, y: 4), 0.98)
    }

    private func pngData(
        width: Int,
        height: Int,
        colorAt: (Int, Int) -> NSColor
    ) throws -> Data {
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: .alphaNonpremultiplied,
                bytesPerRow: width * 4,
                bitsPerPixel: 32
            )
        )

        for y in 0..<height {
            for x in 0..<width {
                rep.setColor(colorAt(x, y), atX: x, y: y)
            }
        }

        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    private func alpha(in rep: NSBitmapImageRep, x: Int, y: Int) throws -> CGFloat {
        try XCTUnwrap(rep.colorAt(x: x, y: y)).alphaComponent
    }

    private static let white = NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1)
    private static let red = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
    private static let clear = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0)
}
