import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    @ViewBuilder
    func contextualActionCard(
        for item: UpcomingItem,
        showsFootballCompetitionLine: Bool,
        snapshot: LayoutSnapshot
    ) -> some View {
        let previewKind = snapshot.contextualPreviewKind(for: item)
        let previewLocationText: String? = {
            if case let .location(locationText)? = previewKind {
                return locationText
            }
            return nil
        }()
        let previewOrganizer: MeetingOrganizer? = {
            if case let .attendees(organizer, _)? = previewKind {
                return organizer
            }
            return nil
        }()
        let previewAttendees: [MeetingAttendee]? = {
            if case let .attendees(_, attendees)? = previewKind {
                return attendees
            }
            return nil
        }()

        let footballLayoutItemCount = snapshot.contextualFootballLayoutItemCount
        let shouldShowLocationPreview = previewLocationText != nil
            && Self.shouldShowContextualMapPreview(
                for: item,
                contextualItemCount: footballLayoutItemCount
            )
        let shouldShowAttendeePreview = previewAttendees != nil
        let shouldShowJoinButton = shouldShowAttendeePreview && item.meetingURL != nil
        let shouldShowDaylightPreview = {
            if case .daylight = previewKind {
                return true
            }
            return false
        }()
        let mapPreviewHeight: CGFloat = snapshot.shouldUseSplitDropdownLayout ? 96 : 112
        let attendeePreviewListHeight = attendeePreviewMaximumListHeight(
            for: item,
            snapshot: snapshot
        )
        let footballContentLevel = snapshot.contextualFootballContentLevel
        let now = displayReferenceDate
        let cardContentWidth = contextualPanelContentWidth(snapshot: snapshot)

        VStack(alignment: .leading, spacing: 6) {
            if let footballMatch = item.footballMatch {
                contextualFootballHeader(
                    for: item,
                    match: footballMatch,
                    showsFootballCompetitionLine: showsFootballCompetitionLine,
                    previewLocationText: previewLocationText,
                    now: now,
                    contextualItemCount: footballLayoutItemCount
                )
                .frame(width: cardContentWidth, alignment: .topLeading)
                .clipped()
            } else {
                if shouldShowDaylightPreview {
                    contextualDaylightHeader(for: item)
                        .frame(width: cardContentWidth, alignment: .topLeading)
                        .clipped()
                } else {
                    contextualProgressHeader(
                        for: item,
                        locationText: previewLocationText,
                        showsJoinButton: shouldShowJoinButton
                    )
                    .frame(width: cardContentWidth, alignment: .topLeading)
                    .clipped()
                }
            }

            if shouldShowLocationPreview,
               let locationText = previewLocationText {
                MiniLocationMapView(
                    locationText: locationText,
                    locationCoordinate: item.locationCoordinate,
                    preferredHeight: mapPreviewHeight
                )
                    .frame(width: cardContentWidth, alignment: .topLeading)
                    .clipped()
                    .id("\(item.notificationKey)|\(locationText)")
            } else if shouldShowAttendeePreview,
                      let previewAttendees {
                MeetingAttendeesPreview(
                    organizer: previewOrganizer,
                    attendees: previewAttendees,
                    listHeight: attendeePreviewListHeight,
                    columnCount: 1
                )
                    .frame(width: cardContentWidth, alignment: .topLeading)
                    .clipped()
                    .id("\(item.notificationKey)|attendees")
            } else if shouldShowDaylightPreview {
                contextualDaylightPreview(
                    for: item,
                    preferredHeight: mapPreviewHeight
                )
                .frame(width: cardContentWidth, alignment: .topLeading)
                .clipped()
            }

            if let footballMatch = item.footballMatch {
                let usesExpandedFootballHeader = Self.shouldUseExpandedContextualFootballHeader(
                    for: footballMatch,
                    itemCount: footballLayoutItemCount
                )
                let scorePlacement = Self.footballContextualScorePlacement(
                    for: footballMatch,
                    itemCount: footballLayoutItemCount
                )
                let outcomeProbabilities = CalendarMonitor.footballOutcomeProbabilities(
                    for: footballMatch,
                    now: now
                )

                if usesExpandedFootballHeader && scorePlacement == .headline {
                    FootballMatchSectionHeaderView(
                        match: footballMatch,
                        display: item.footballMenuBarDisplay,
                        showsScore: true,
                        showsTeamNames: true,
                        showsTeamLogos: true,
                        availableWidth: cardContentWidth
                    )
                }

                if footballContentLevel.showsStats && footballMatch.statusState != .scheduled {
                    FootballMatchStatsSection(
                        match: footballMatch,
                        display: item.footballMenuBarDisplay,
                        showsScoreHeader: Self.footballContextualScorePlacement(
                            for: footballMatch,
                            itemCount: footballLayoutItemCount
                        ) == .stats,
                        outcomeProbabilities: outcomeProbabilities,
                        availableWidth: cardContentWidth
                    )
                }

                if Self.shouldShowStandaloneContextualFootballOutcomeProbabilities(
                    for: footballMatch,
                    itemCount: footballLayoutItemCount
                ),
                   let outcomeProbabilities {
                    FootballOutcomeProbabilityBar(
                        match: footballMatch,
                        display: item.footballMenuBarDisplay,
                        probabilities: outcomeProbabilities,
                        style: footballLayoutItemCount <= 1 ? .contextual : .compact,
                        availableWidth: cardContentWidth
                    )
                }

                if footballContentLevel.showsGoalScorers,
                   footballMatch.totalGoals > 0 {
                    FootballGoalScorersSection(
                        match: footballMatch,
                        display: item.footballMenuBarDisplay,
                        showsTeamHeader: Self.shouldShowGoalScorersSectionHeader(for: footballLayoutItemCount),
                        showsScoreHeader: Self.footballContextualScorePlacement(
                            for: footballMatch,
                            itemCount: footballLayoutItemCount
                        ) == .goalScorers,
                        availableWidth: cardContentWidth
                    )
                }
            }

        }
        .frame(width: cardContentWidth, alignment: .leading)
        .clipped()
    }

    func contextualFootballHeader(
        for item: UpcomingItem,
        match footballMatch: FootballFixtureMatch,
        showsFootballCompetitionLine: Bool,
        previewLocationText: String?,
        now: Date,
        contextualItemCount: Int
    ) -> some View {
        MenuContentHoverContainer { isHovered in
            contextualFootballHeaderContent(
                for: item,
                match: footballMatch,
                showsFootballCompetitionLine: showsFootballCompetitionLine,
                previewLocationText: previewLocationText,
                now: now,
                contextualItemCount: contextualItemCount,
                isHovered: isHovered
            )
        }
    }

    func contextualFootballHeaderContent(
        for item: UpcomingItem,
        match footballMatch: FootballFixtureMatch,
        showsFootballCompetitionLine: Bool,
        previewLocationText: String?,
        now: Date,
        contextualItemCount: Int,
        isHovered: Bool
    ) -> some View {
        HStack(spacing: 8) {
            let scheduleText = Self.footballContextualScheduleText(for: footballMatch, now: now)
            let venueName = footballContextualVenueName(for: item, match: footballMatch)
            let usesExpandedFootballHeader = Self.shouldUseExpandedContextualFootballHeader(
                for: footballMatch,
                itemCount: contextualItemCount
            )

            VStack(alignment: .leading, spacing: 2) {
                if !usesExpandedFootballHeader {
                    HStack(alignment: .top, spacing: 10) {
                        footballFixtureHeadline(
                            match: footballMatch,
                            display: item.footballMenuBarDisplay,
                            font: MenuMarkerMetrics.contextualHeadlineFont,
                            showsScore: true,
                            showsInlineAggregate: true,
                            showsCardBadges: true,
                            showsStatusAccessories: true
                        )
                    }
                }

                if footballInlineAggregateText(for: footballMatch) == nil,
                   footballFixtureContextBadgeText(for: footballMatch) != nil {
                    HStack {
                        footballFixtureContextBadge(for: footballMatch)
                        Spacer(minLength: 0)
                    }
                }

                if let venueName {
                    HStack(alignment: .center, spacing: 4) {
                        Image(systemName: locationSymbolName(for: item))
                            .font(.system(size: MenuMarkerMetrics.symbolSize, weight: .regular))
                            .frame(
                                width: MenuMarkerMetrics.symbolSize,
                                height: MenuMarkerMetrics.symbolSize,
                                alignment: .center
                            )
                            .foregroundStyle(.secondary)

                        Text(venueName)
                            .font(MenuMarkerMetrics.rowDetailFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 8)

                        if !isHovered,
                           let scheduleText,
                           !scheduleText.isEmpty {
                            Text(scheduleText)
                                .font(MenuMarkerMetrics.contextualMetadataEmphasisFont)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                } else if !isHovered,
                          let scheduleText,
                          !scheduleText.isEmpty {
                    HStack {
                        Spacer(minLength: 0)
                        Text(scheduleText)
                            .font(MenuMarkerMetrics.contextualMetadataEmphasisFont)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                if showsFootballCompetitionLine {
                    footballCompetitionLine(
                        match: footballMatch,
                        display: item.footballMenuBarDisplay,
                        font: MenuMarkerMetrics.rowDetailFont
                    )
                }
            }

            Spacer(minLength: 8)

            if isHovered {
                contextualActionButtons(for: item, locationText: previewLocationText)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .menuRowHoverBackground(isHovered: isHovered)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    func contextualProgressHeader(
        for item: UpcomingItem,
        locationText: String?,
        showsJoinButton: Bool
    ) -> some View {
        MenuContentHoverContainer { isHovered in
            contextualProgressHeaderContent(
                for: item,
                locationText: locationText,
                showsJoinButton: showsJoinButton,
                isHovered: isHovered
            )
        }
    }

    @ViewBuilder
    func contextualProgressHeaderContent(
        for item: UpcomingItem,
        locationText: String?,
        showsJoinButton: Bool,
        isHovered: Bool
    ) -> some View {
        let now = displayReferenceDate
        let headerHeight = contextualProgressHeaderHeight(for: item)
        let reservedTrailingWidth = isHovered ? contextualActionRowWidth(
            for: item,
            locationText: locationText,
            showsJoinButton: showsJoinButton
        ) : 0

        ZStack(alignment: .trailing) {
            rowPrimaryContent(
                for: item,
                now: now,
                isHovered: isHovered,
                hideTimeDetails: isHovered,
                reservedTrailingWidth: reservedTrailingWidth
            )
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: headerHeight, alignment: .topLeading)

            if isHovered {
                contextualActionButtons(
                    for: item,
                    locationText: locationText,
                    showsJoinButton: showsJoinButton
                )
                .padding(.trailing, MenuActionControlMetrics.trailingInset)
            }
        }
        .frame(height: headerHeight, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
    }

    func contextualProgressHeaderHeight(for item: UpcomingItem) -> CGFloat {
        let hasVirtualLocation = monitor.isVirtualLocationText(item.locationText)
        let showsTravelTime = item.kind == .event
            && !item.isAllDay
            && item.meetingURL == nil
            && !hasVirtualLocation
            && (item.travelTimeMinutes ?? 0) > 0
        let allDayRightLabel = monitor.allDayLabel(
            for: item,
            now: displayReferenceDate,
            simplified: settings.useSimplifiedCountdown
        )
        let showRightTimeColumn = item.kind == .event && (!item.isAllDay || allDayRightLabel != nil)

        return rowPrimaryContentMinimumHeight(
            for: item,
            showsTravelTime: showsTravelTime,
            showRightTimeColumn: showRightTimeColumn
        )
    }

}
