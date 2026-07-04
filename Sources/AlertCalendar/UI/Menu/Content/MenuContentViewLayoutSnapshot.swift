import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    struct LayoutSnapshot {
        let filteredAlertDescriptions: [String]
        let contextualActionCandidates: [UpcomingItem]
        let contextualPreviewActionItems: [UpcomingItem]
        let footballContextualActionItems: [UpcomingItem]
        let displayedContextualActionItems: [UpcomingItem]
        let contextualPreviewKindsByKey: [String: ContextualPreviewKind]
        let queueItemsSource: [UpcomingItem]
        let queueItemsForSingleColumnLayout: [UpcomingItem]
        let queueItemsForSplitLayout: [UpcomingItem]
        let queueItemsForActions: [UpcomingItem]
        let shouldUseSplitDropdownLayout: Bool
        let dropdownMinimumWidth: CGFloat
        let sharedContextualFootballMatches: [FootballFixtureMatch]?
        let sharedContextualFootballCompetitionTitle: String?
        let sharedContextualFootballCompetitionLogoPath: String?
        let sharedContextualFootballCompetitionLogoURL: URL?
        let contextualFootballLayoutItemCount: Int
        let contextualFootballContentLevel: FootballContextualContentLevel

        var contextualSharedCompetitionIsActive: Bool {
            sharedContextualFootballCompetitionTitle != nil
        }

        func contextualPreviewKind(for item: UpcomingItem) -> ContextualPreviewKind? {
            contextualPreviewKindsByKey[item.notificationKey]
        }
    }

    var layoutSnapshot: LayoutSnapshot {
        let now = displayReferenceDate
        let futureWindowEnd = dropdownFutureWindowEnd(now: now)
        let allDayItems = monitor.allDayEventItems
        let eventWindowItems = monitor.upcomingItems.filter {
            $0.kind == .event && Self.shouldIncludeInDropdownTimeWindow(
                $0,
                now: now,
                futureWindowEnd: futureWindowEnd
            )
        }
        let allEventItems = deduplicatedItems((allDayItems + eventWindowItems).sorted { $0.date < $1.date })
        var contextualPreviewKindsByKey: [String: ContextualPreviewKind] = [:]
        let contextualCandidates = allEventItems.filter { item in
            guard shouldShowContextualPreview(for: item, now: now),
                  let previewKind = contextualPreviewKind(for: item) else {
                return false
            }

            contextualPreviewKindsByKey[item.notificationKey] = previewKind
            return true
        }
        let contextualPreviewItems = Self.contextualActionItems(
            from: contextualCandidates,
            now: now
        )
        let nonFootballContextualItems = Self.contextualActionItems(
            from: contextualCandidates.filter { $0.footballMatch == nil },
            now: now
        )
        let footballContextualItems = Self.footballContextualActionItems(
            from: contextualCandidates,
            now: now
        )
        let splitContextualItems = Self.splitContextualActionItems(
            contextualItems: contextualPreviewItems + nonFootballContextualItems,
            footballItems: footballContextualItems,
            previewKindsByKey: contextualPreviewKindsByKey
        )

        let queueWindowItems = monitor.upcomingItems.filter {
            ($0.kind == .event || $0.kind == .reminder) && Self.shouldIncludeInDropdownTimeWindow(
                $0,
                now: now,
                futureWindowEnd: futureWindowEnd
            )
        }
        let queueSource = deduplicatedItems((allDayItems + queueWindowItems).sorted { $0.date < $1.date })
        let singleColumnQueueItems = Self.queueItemsForActions(
            from: queueSource,
            contextualItems: contextualPreviewItems,
            now: now,
            futureWindowEnd: futureWindowEnd,
            maxItems: max(1, settings.maxListItems)
        )
        let splitQueueItems = Self.queueItemsForActions(
            from: queueSource,
            contextualItems: splitContextualItems,
            now: now,
            futureWindowEnd: futureWindowEnd,
            maxItems: max(1, settings.maxListItems)
        )
        let usesSplitLayout = shouldUseHeightConstrainedSplitLayout(
            contextualItems: splitContextualItems,
            previewKindsByKey: contextualPreviewKindsByKey,
            queueItems: splitQueueItems,
            alertCount: filteredAlertDescriptions.count
        )
        let displayedContextualItems = usesSplitLayout ? splitContextualItems : contextualPreviewItems
        let displayedQueueItems = usesSplitLayout ? splitQueueItems : singleColumnQueueItems
        let footballLayoutItemCount = Self.contextualFootballLayoutItemCount(from: displayedContextualItems)
        let dropdownMinimumWidth: CGFloat = {
            guard !usesSplitLayout else {
                return splitDropdownWidth(
                    contextualItems: splitContextualItems,
                    previewKindsByKey: contextualPreviewKindsByKey
                )
            }
            let contextualWidth = displayedContextualItems.reduce(minimumSingleColumnDropdownWidth) { partialResult, item in
                max(
                    partialResult,
                    contextualCardMinimumWidth(
                        for: item,
                        previewKind: contextualPreviewKindsByKey[item.notificationKey]
                    )
                )
            }
            let queueWidth = displayedQueueItems.reduce(minimumSingleColumnDropdownWidth) { partialResult, item in
                max(partialResult, queueItemMinimumWidth(for: item))
            }
            return resolvedSingleColumnDropdownWidth(
                contextualWidth: contextualWidth,
                queueWidth: queueWidth
            )
        }()
        let footballMatches: [FootballFixtureMatch]? = {
            guard !displayedContextualItems.isEmpty else { return nil }
            let matches = displayedContextualItems.compactMap(\.footballMatch)
            guard matches.count == displayedContextualItems.count else { return nil }
            return matches
        }()
        let sharedCompetitionTitle = footballMatches.flatMap {
            FootballFixtureFormatter.sharedCompetitionTitle(for: $0)
        }

        return LayoutSnapshot(
            filteredAlertDescriptions: filteredAlertDescriptions,
            contextualActionCandidates: contextualCandidates,
            contextualPreviewActionItems: contextualPreviewItems,
            footballContextualActionItems: footballContextualItems,
            displayedContextualActionItems: displayedContextualItems,
            contextualPreviewKindsByKey: contextualPreviewKindsByKey,
            queueItemsSource: queueSource,
            queueItemsForSingleColumnLayout: singleColumnQueueItems,
            queueItemsForSplitLayout: splitQueueItems,
            queueItemsForActions: displayedQueueItems,
            shouldUseSplitDropdownLayout: usesSplitLayout,
            dropdownMinimumWidth: dropdownMinimumWidth,
            sharedContextualFootballMatches: footballMatches,
            sharedContextualFootballCompetitionTitle: sharedCompetitionTitle,
            sharedContextualFootballCompetitionLogoPath: sharedCompetitionTitle == nil ? nil : displayedContextualItems.first?.footballMenuBarDisplay?.competitionLocalLogoPath,
            sharedContextualFootballCompetitionLogoURL: sharedCompetitionTitle == nil ? nil : footballMatches?.first?.competitionLogoURL,
            contextualFootballLayoutItemCount: footballLayoutItemCount,
            contextualFootballContentLevel: Self.contextualFootballContentLevel(for: footballLayoutItemCount)
        )
    }
}
