import AppKit
import SwiftUI

enum MenuMarkerMetrics {
    static let symbolSize: CGFloat = 12
    static let rowTitleSize: CGFloat = 12
    static let rowDetailSize: CGFloat = 11
    static let compactMetadataSize: CGFloat = 10

    static let rowTitleFont = Font.system(size: rowTitleSize, weight: .semibold)
    static let rowDetailFont = Font.system(size: rowDetailSize, weight: .medium)
    static let actionLabelFont = Font.system(size: rowDetailSize, weight: .semibold)
    static let compactMetadataFont = Font.system(size: compactMetadataSize, weight: .semibold)

    static var rowTitleNSFont: NSFont {
        NSFont.systemFont(ofSize: rowTitleSize, weight: .semibold)
    }

    static var rowDetailNSFont: NSFont {
        NSFont.systemFont(ofSize: rowDetailSize, weight: .medium)
    }

    static var actionLabelNSFont: NSFont {
        NSFont.systemFont(ofSize: rowDetailSize, weight: .semibold)
    }
}
