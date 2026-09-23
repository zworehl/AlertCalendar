import AppKit
import Combine
import Foundation

struct MenuBarPresentationState: Equatable {
    var label: String
    var color: NSColor
    var alertedSegmentIndex: Int?
    var alertTextOpacity: CGFloat
    var dotColors: [NSColor]
    var markerStyles: [MenuMarkerStyle]
    var segments: [String]
    var segmentBackgroundColors: [NSColor]
    var segmentBackgroundProgresses: [CGFloat]
    var segmentParticipationStatuses: [EventParticipationStatus?]
    var segmentTextureStatuses: [EventParticipationStatus?]
    var segmentAccessorySymbolNames: [[String]]
    var footballDisplay: FootballMenuBarDisplay?
    var footballTrailingText: String?
    var footballStatusText: String?
    var footballStatusColor: NSColor
    var footballGoalHighlightSide: FootballScoreSide?
    var footballGoalHighlightTextOpacity: CGFloat
    var fullTitleText: String? = nil

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
        segmentParticipationStatuses: [nil],
        segmentTextureStatuses: [nil],
        segmentAccessorySymbolNames: [[]],
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
            segmentParticipationStatuses: [nil],
            segmentTextureStatuses: [nil],
            segmentAccessorySymbolNames: [[]],
            footballDisplay: nil,
            footballTrailingText: nil,
            footballStatusText: nil,
            footballStatusColor: .systemGreen,
            footballGoalHighlightSide: nil,
            footballGoalHighlightTextOpacity: 0
        )
    }

    static func == (lhs: MenuBarPresentationState, rhs: MenuBarPresentationState) -> Bool {
        lhs.label == rhs.label
            && lhs.fullTitleText == rhs.fullTitleText
            && lhs.color.isEqual(rhs.color)
            && lhs.alertedSegmentIndex == rhs.alertedSegmentIndex
            && lhs.alertTextOpacity == rhs.alertTextOpacity
            && colorsAreEqual(lhs.dotColors, rhs.dotColors)
            && lhs.markerStyles == rhs.markerStyles
            && lhs.segments == rhs.segments
            && colorsAreEqual(lhs.segmentBackgroundColors, rhs.segmentBackgroundColors)
            && lhs.segmentBackgroundProgresses == rhs.segmentBackgroundProgresses
            && lhs.segmentParticipationStatuses == rhs.segmentParticipationStatuses
            && lhs.segmentTextureStatuses == rhs.segmentTextureStatuses
            && lhs.segmentAccessorySymbolNames == rhs.segmentAccessorySymbolNames
            && lhs.footballDisplay == rhs.footballDisplay
            && lhs.footballTrailingText == rhs.footballTrailingText
            && lhs.footballStatusText == rhs.footballStatusText
            && lhs.footballStatusColor.isEqual(rhs.footballStatusColor)
            && lhs.footballGoalHighlightSide == rhs.footballGoalHighlightSide
            && lhs.footballGoalHighlightTextOpacity == rhs.footballGoalHighlightTextOpacity
    }

    private static func colorsAreEqual(_ lhs: [NSColor], _ rhs: [NSColor]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.isEqual($1) }
    }
}

@MainActor
final class MenuBarPresentationModel: ObservableObject {
    @Published private(set) var state: MenuBarPresentationState = .loading
    @Published private(set) var isInitialLoading = true

    func apply(_ state: MenuBarPresentationState) {
        guard self.state != state else { return }
        self.state = state
    }

    func setInitialLoading(_ isLoading: Bool) {
        guard isInitialLoading != isLoading else { return }
        isInitialLoading = isLoading
    }

    func setAlertTextOpacity(_ opacity: CGFloat) {
        guard state.alertTextOpacity != opacity else { return }
        state.alertTextOpacity = opacity
    }
}
