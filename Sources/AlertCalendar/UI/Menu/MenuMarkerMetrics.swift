import AppKit
import SwiftUI

enum MenuMarkerMetrics {
    static let symbolSize: CGFloat = 12
    static let rowTitleSize: CGFloat = NSFont.systemFontSize
    static let rowDetailSize: CGFloat = NSFont.systemFontSize(for: .small)
    static let compactMetadataSize: CGFloat = 10
    static let rowContentVerticalPadding: CGFloat = 5
    static let rowContentTopPadding = rowContentVerticalPadding
    static let rowContentBottomPadding = rowContentVerticalPadding
    static let compactCalendarMarkerHeight: CGFloat = 12
    static let rowLayoutLineHeight: CGFloat = 16
    static let rowMinimumVerticalAllowance: CGFloat = 12
    static let singleLineRowMinimumHeight: CGFloat = 34

    static let rowTitleFont = Font.system(size: rowTitleSize, weight: .regular)
    static let rowDetailFont = Font.system(size: rowDetailSize, weight: .regular)
    static let contextualHeadlineFont = Font.system(size: rowTitleSize, weight: .semibold)
    static let contextualMetadataEmphasisFont = Font.system(size: rowDetailSize, weight: .semibold)
    static let compactMetadataFont = Font.system(size: compactMetadataSize, weight: .semibold)

    static var rowTitleNSFont: NSFont {
        NSFont.systemFont(ofSize: rowTitleSize, weight: .regular)
    }

    static var rowDetailNSFont: NSFont {
        NSFont.systemFont(ofSize: rowDetailSize, weight: .regular)
    }

    /// Centers a 12-point marker on the first system-font title line. Keeping
    /// this independent of the row's total height prevents multi-line metadata
    /// from pulling the marker away from its title.
    static var markerFirstLineTopPadding: CGFloat {
        max(0, (rowTitleLineHeight - symbolSize) / 2)
    }

    /// The time column uses the small system font but shares the title's
    /// optical center rather than merely sharing its top edge.
    static var detailFirstLineTopPadding: CGFloat {
        max(0, (rowTitleLineHeight - rowDetailLineHeight) / 2)
    }

    static var rowTitleLineHeight: CGFloat {
        ceil(rowTitleNSFont.boundingRectForFont.height)
    }

    static var rowDetailLineHeight: CGFloat {
        ceil(rowDetailNSFont.boundingRectForFont.height)
    }

    /// A detailed event marker is inset equally from the first and last line.
    /// This keeps its bottom edge aligned with the final line instead of
    /// extending past it by the first-line optical offset.
    static var detailedCalendarMarkerHeight: CGFloat {
        calendarMarkerHeight(lineCount: 2)
    }

    static func calendarMarkerHeight(lineCount: Int) -> CGFloat {
        let resolvedLineCount = max(1, lineCount)
        let textHeight = rowTitleLineHeight
            + CGFloat(resolvedLineCount - 1) * rowDetailLineHeight
        return max(
            compactCalendarMarkerHeight,
            textHeight - (markerFirstLineTopPadding * 2)
        )
    }
}
