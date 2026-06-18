import AppKit
import XCTest
@testable import AlertCalendar

@MainActor
final class MenuBarStatusLabelTests: XCTestCase {
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
            awayLocalLogoPath: nil
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
}
