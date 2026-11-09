import Foundation

struct PinnedFootballMenuBarScore: Equatable, Identifiable {
    let id: String
    let calendarColor: AlertCalendarColor
    let backgroundProgress: CGFloat
    let display: FootballMenuBarDisplay
    let statusText: String?
    let highlightSide: FootballScoreSide?
    let highlightOpacity: CGFloat
}

extension CalendarMonitor {
    nonisolated static func rotatingPinnedFootballMenuBarScore(
        from scores: [PinnedFootballMenuBarScore],
        now: Date,
        rotationInterval: TimeInterval,
        rotationState: inout MenuBarRotationState
    ) -> PinnedFootballMenuBarScore? {
        rotationState = resolvedMenuBarRotationState(
            for: scores.map(\.id),
            now: now,
            rotationInterval: rotationInterval,
            previousState: rotationState,
            allowMissingSelectedKeyHold: false
        )
        return scores.first { $0.id == rotationState.selectedKey }
    }

    nonisolated static func shouldPinLiveFootballItem(_ item: UpcomingItem, settings: AppSettings) -> Bool {
        settings.pinLiveFootballScoresInMenuBar && item.footballMatch?.statusState == .inProgress
    }

    func pinnedFootballMenuBarScores(now: Date, settings: AppSettings) -> [PinnedFootballMenuBarScore] {
        guard settings.pinLiveFootballScoresInMenuBar else { return [] }
        var seen: Set<String> = []
        return allMenuBarCandidateItems()
            .filter { Self.shouldPinLiveFootballItem($0, settings: settings) }
            .sorted { ($0.date, $0.id) < ($1.date, $1.id) }
            .compactMap { item -> PinnedFootballMenuBarScore? in
                guard let match = item.footballMatch, seen.insert(match.id).inserted else { return nil }
                let highlight = activeFootballGoalHighlight.flatMap { $0.matchID == match.id ? $0 : nil }
                return PinnedFootballMenuBarScore(
                    id: match.id,
                    calendarColor: item.calendarColor,
                    backgroundProgress: activeEventProgress(for: item, now: now, settings: settings) ?? 1,
                    display: footballMenuBarDisplay(for: match),
                    statusText: Self.resolvedFootballMenuBarStatusText(for: match, now: now),
                    highlightSide: highlight?.scoringSide,
                    highlightOpacity: highlight != nil && Int(now.timeIntervalSinceReferenceDate).isMultiple(of: 2) ? 1 : 0
                )
            }
    }
}
