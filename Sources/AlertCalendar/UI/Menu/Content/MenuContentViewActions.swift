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

        let shouldShowLocationPreview = previewLocationText != nil
            && Self.shouldShowContextualMapPreview(
                for: item,
                concurrentFootballMatchCount: snapshot.footballContextualActionItems.count
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
        let attendeePreviewListHeight: CGFloat = snapshot.shouldUseSplitDropdownLayout ? 148 : 188
        let footballContentLevel = snapshot.contextualFootballContentLevel
        let now = displayReferenceDate
        let concurrentFootballMatchCount = snapshot.displayedContextualActionItems.filter {
            $0.footballMatch != nil
        }.count

        VStack(alignment: .leading, spacing: 6) {
            if let footballMatch = item.footballMatch {
                contextualFootballHeader(
                    for: item,
                    match: footballMatch,
                    showsFootballCompetitionLine: showsFootballCompetitionLine,
                    previewLocationText: previewLocationText,
                    now: now,
                    concurrentFootballMatchCount: concurrentFootballMatchCount
                )
            } else {
                if shouldShowDaylightPreview {
                    contextualDaylightHeader(for: item)
                } else {
                    contextualProgressHeader(
                        for: item,
                        locationText: previewLocationText,
                        showsJoinButton: shouldShowJoinButton
                    )
                }
            }

            if shouldShowLocationPreview,
               let locationText = previewLocationText {
                MiniLocationMapView(
                    locationText: locationText,
                    preferredHeight: mapPreviewHeight
                )
                    .id("\(item.notificationKey)|\(locationText)")
            } else if shouldShowAttendeePreview,
                      let previewAttendees {
                MeetingAttendeesPreview(
                    organizer: previewOrganizer,
                    attendees: previewAttendees,
                    listHeight: attendeePreviewListHeight
                )
                    .id("\(item.notificationKey)|attendees")
            } else if shouldShowDaylightPreview {
                contextualDaylightPreview(
                    for: item,
                    preferredHeight: mapPreviewHeight
                )
            }

            if let footballMatch = item.footballMatch {
                let usesExpandedFootballHeader = Self.shouldUseExpandedContextualFootballHeader(
                    for: footballMatch,
                    itemCount: concurrentFootballMatchCount
                )
                let scorePlacement = Self.footballContextualScorePlacement(
                    for: footballMatch,
                    itemCount: concurrentFootballMatchCount
                )

                if usesExpandedFootballHeader && scorePlacement == .headline {
                    FootballMatchSectionHeaderView(
                        match: footballMatch,
                        display: item.footballMenuBarDisplay,
                        showsScore: true,
                        showsTeamNames: true,
                        showsTeamLogos: true
                    )
                }

                if footballContentLevel.showsStats {
                    FootballMatchStatsSection(
                        match: footballMatch,
                        display: item.footballMenuBarDisplay,
                        showsScoreHeader: Self.footballContextualScorePlacement(
                            for: footballMatch,
                            itemCount: concurrentFootballMatchCount
                        ) == .stats
                    )
                }

                if footballContentLevel.showsGoalScorers,
                   footballMatch.totalGoals > 0 {
                    FootballGoalScorersSection(
                        match: footballMatch,
                        display: item.footballMenuBarDisplay,
                        showsTeamHeader: Self.shouldShowGoalScorersSectionHeader(for: concurrentFootballMatchCount),
                        showsScoreHeader: Self.footballContextualScorePlacement(
                            for: footballMatch,
                            itemCount: concurrentFootballMatchCount
                        ) == .goalScorers
                    )
                }
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func contextualFootballHeader(
        for item: UpcomingItem,
        match footballMatch: FootballFixtureMatch,
        showsFootballCompetitionLine: Bool,
        previewLocationText: String?,
        now: Date,
        concurrentFootballMatchCount: Int
    ) -> some View {
        MenuContentHoverContainer { isHovered in
            contextualFootballHeaderContent(
                for: item,
                match: footballMatch,
                showsFootballCompetitionLine: showsFootballCompetitionLine,
                previewLocationText: previewLocationText,
                now: now,
                concurrentFootballMatchCount: concurrentFootballMatchCount,
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
        concurrentFootballMatchCount: Int,
        isHovered: Bool
    ) -> some View {
        HStack(spacing: 8) {
            let scheduleText = Self.footballContextualScheduleText(for: footballMatch, now: now)
            let venueName = footballContextualVenueName(for: item, match: footballMatch)
            let usesExpandedFootballHeader = Self.shouldUseExpandedContextualFootballHeader(
                for: footballMatch,
                itemCount: concurrentFootballMatchCount
            )

            VStack(alignment: .leading, spacing: 2) {
                if !usesExpandedFootballHeader {
                    HStack(alignment: .top, spacing: 10) {
                        footballFixtureHeadline(
                            match: footballMatch,
                            display: item.footballMenuBarDisplay,
                            font: .subheadline.weight(.semibold),
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
                            .font(.system(size: 12, weight: .regular))
                            .frame(width: 12, height: 12, alignment: .center)
                            .foregroundStyle(.secondary)

                        Text(venueName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 8)

                        if !isHovered,
                           let scheduleText,
                           !scheduleText.isEmpty {
                            Text(scheduleText)
                                .font(.caption.weight(.semibold))
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
                            .font(.caption.weight(.semibold))
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
                        font: .caption
                    )
                }
            }

            Spacer(minLength: 8)

            if isHovered {
                contextualActionButtons(for: item, locationText: previewLocationText)
            }
        }
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
                .padding(.trailing, 6)
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
        let showsLocation = item.kind == .event
            && !item.isAllDay
            && item.locationText.map {
                shouldShowLocationRow(
                    locationName: displayLocationName(from: $0),
                    meetingURL: item.meetingURL
                )
            } == true
        let showsMeetingLink = item.meetingURL != nil
        let lineCount = 1
            + (showsTravelTime ? 1 : 0)
            + ((showsLocation || showsMeetingLink) ? 1 : 0)

        return max(34, CGFloat(lineCount * 16) + 12)
    }

}
