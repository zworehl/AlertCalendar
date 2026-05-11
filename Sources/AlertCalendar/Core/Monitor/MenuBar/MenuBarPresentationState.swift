import AppKit
import Foundation

struct MenuBarPresentationState {
    var label: String
    var color: NSColor
    var alertedSegmentIndex: Int?
    var alertTextOpacity: CGFloat
    var dotColors: [NSColor]
    var markerStyles: [MenuMarkerStyle]
    var segments: [String]
    var segmentBackgroundColors: [NSColor]
    var segmentBackgroundProgresses: [CGFloat]
    var footballDisplay: FootballMenuBarDisplay?
    var footballTrailingText: String?
    var footballStatusText: String?
    var footballStatusColor: NSColor
    var footballGoalHighlightSide: FootballScoreSide?
    var footballGoalHighlightTextOpacity: CGFloat

    static let loading = MenuBarPresentationState(
        label: "Loading...",
        color: .systemGray,
        alertedSegmentIndex: nil,
        alertTextOpacity: 0,
        dotColors: [.systemGray],
        markerStyles: [.color(.systemGray)],
        segments: ["Loading..."],
        segmentBackgroundColors: [.clear],
        segmentBackgroundProgresses: [0],
        footballDisplay: nil,
        footballTrailingText: nil,
        footballStatusText: nil,
        footballStatusColor: .systemGreen,
        footballGoalHighlightSide: nil,
        footballGoalHighlightTextOpacity: 0
    )

    static func empty(text: String) -> MenuBarPresentationState {
        MenuBarPresentationState(
            label: text,
            color: .systemGray,
            alertedSegmentIndex: nil,
            alertTextOpacity: 0,
            dotColors: [.systemGray],
            markerStyles: [.color(.systemGray)],
            segments: [text],
            segmentBackgroundColors: [.clear],
            segmentBackgroundProgresses: [0],
            footballDisplay: nil,
            footballTrailingText: nil,
            footballStatusText: nil,
            footballStatusColor: .systemGreen,
            footballGoalHighlightSide: nil,
            footballGoalHighlightTextOpacity: 0
        )
    }
}
