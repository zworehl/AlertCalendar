import AppKit
import SwiftUI

extension MenuBarStatusLabel {
    @MainActor
    static func makeCombinedBadgeImage(
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
        footballLogoRevision: Int,
        pinnedScores: [PinnedFootballMenuBarScore]
    ) -> NSImage {
        let eventImage = makeBadgeImage(
            text: text, color: color, alertedSegmentIndex: alertedSegmentIndex,
            alertTextOpacity: alertTextOpacity, dotColors: dotColors, markerStyles: markerStyles,
            segments: segments, segmentBackgroundColors: segmentBackgroundColors,
            segmentBackgroundProgresses: segmentBackgroundProgresses,
            segmentParticipationStatuses: segmentParticipationStatuses,
            segmentTextureStatuses: segmentTextureStatuses,
            segmentAccessorySymbolNames: segmentAccessorySymbolNames,
            footballDisplay: footballDisplay, footballTrailingText: footballTrailingText,
            footballStatusText: footballStatusText, footballStatusColor: footballStatusColor,
            footballGoalHighlightSide: footballGoalHighlightSide,
            footballGoalHighlightTextOpacity: footballGoalHighlightTextOpacity,
            fontSize: fontSize, footballLogoRevision: footballLogoRevision
        )
        let scoreImages = pinnedScores.map { score in
            makeBadgeImage(
                text: score.display.accessibilityText, color: score.calendarColor.nsColor,
                alertedSegmentIndex: nil, alertTextOpacity: 0, dotColors: [], markerStyles: [],
                segments: [score.display.accessibilityText], segmentBackgroundColors: [score.calendarColor.nsColor.withAlphaComponent(0.30)],
                segmentBackgroundProgresses: [score.backgroundProgress], segmentParticipationStatuses: [nil],
                segmentTextureStatuses: [nil], segmentAccessorySymbolNames: [[]],
                footballDisplay: score.display, footballTrailingText: nil,
                footballStatusText: score.statusText, footballStatusColor: score.calendarColor.nsColor,
                footballGoalHighlightSide: score.highlightSide,
                footballGoalHighlightTextOpacity: score.highlightOpacity,
                fontSize: fontSize, footballLogoRevision: footballLogoRevision
            )
        }
        return combinedBadgeImage(event: eventImage, scores: scoreImages)
    }

    @MainActor
    static func combinedBadgeImage(event: NSImage, scores: [NSImage]) -> NSImage {
        guard !scores.isEmpty else { return event }
        let images = [event] + scores
        let spacing: CGFloat = 6
        let size = CGSize(
            width: images.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(scores.count),
            height: images.map(\.size.height).max() ?? event.size.height
        )
        let combined = NSImage(size: size)
        combined.lockFocus()
        var x: CGFloat = 0
        for image in images {
            image.draw(in: CGRect(x: x, y: (size.height - image.size.height) / 2,
                                  width: image.size.width, height: image.size.height))
            x += image.size.width + spacing
        }
        combined.unlockFocus()
        return combined
    }

}
