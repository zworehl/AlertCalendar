import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    func meetingServiceName(for url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        let scheme = (url.scheme ?? "").lowercased()
        let absolute = url.absoluteString.lowercased()

        if host.contains("meet.google.") {
            return "Meet"
        }
        if host.contains("zoom.") || host.contains("us02web.zoom.") {
            return "Zoom"
        }
        if scheme == "msteams"
            || scheme == "microsoftteams"
            || host.contains("teams.")
            || host.contains("teams.microsoft.")
            || host.contains("teams.live.")
            || host.contains("teams.office.")
            || host.contains("aka.ms")
            || host.contains("microsoftteams.")
            || host.contains("teams.ms")
            || absolute.contains("meetup-join")
            || absolute.contains("teams.microsoft.com")
            || absolute.contains("teams.live.com")
            || absolute.contains("teams.office.com") {
            return "Microsoft Teams"
        }
        if host.contains("webex.") {
            return "Webex"
        }
        if host.contains("whereby.") {
            return "Whereby"
        }
        if host.contains("jitsi.") || host.contains("meet.jit.si") {
            return "Jitsi"
        }
        if host.contains("chime.aws") || host.contains("amazonchime.") {
            return "Amazon Chime"
        }

        return "Meeting Link"
    }

    func mapURL(for locationText: String) -> URL? {
        guard let encoded = locationText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "http://maps.apple.com/?q=\(encoded)")
    }

    func preciseMapURL(for coordinate: ResolvedLocationCoordinate, label: String) -> URL? {
        var components = URLComponents(string: "http://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(
                name: "ll",
                value: String(format: "%.6f,%.6f", coordinate.latitude, coordinate.longitude)
            ),
            URLQueryItem(name: "q", value: label),
        ]
        return components?.url
    }

    func openMap(for item: UpcomingItem, locationText: String) {
        let label: String
        if let footballMatch = item.footballMatch {
            label = footballContextualVenueName(for: item, match: footballMatch)
                ?? displayLocationName(from: locationText)
        } else {
            label = displayLocationName(from: locationText)
        }

        Task {
            if let coordinate = await LocationCoordinateResolver.shared.coordinate(for: locationText),
               let preciseURL = preciseMapURL(for: coordinate, label: label) {
                _ = await MainActor.run {
                    NSWorkspace.shared.open(preciseURL)
                }
                return
            }

            if let fallbackURL = mapURL(for: locationText) {
                _ = await MainActor.run {
                    NSWorkspace.shared.open(fallbackURL)
                }
            }
        }
    }

    func shouldShowPhysicalMap(for item: UpcomingItem, locationText: String?) -> Bool {
        guard item.meetingURL == nil else { return false }
        guard let locationText else { return false }
        return !monitor.isVirtualLocationText(locationText)
    }

    func locationTextForMenuBarItem(_ item: UpcomingItem) -> String? {
        if let locationText = item.locationText {
            if monitor.isVirtualLocationText(locationText) {
                return nil
            }
            return locationText
        }
        return nil
    }

    @ViewBuilder
    func contextualActionCard(
        for item: UpcomingItem,
        showsFootballCompetitionLine: Bool
    ) -> some View {
        let previewKind = contextualPreviewKind(for: item)
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
                concurrentFootballMatchCount: footballContextualActionItems.count
            )
        let shouldShowAttendeePreview = previewAttendees != nil
        let shouldShowDaylightPreview = {
            if case .daylight = previewKind {
                return true
            }
            return false
        }()
        let mapPreviewHeight: CGFloat = shouldUseSplitDropdownLayout ? 96 : 112
        let attendeePreviewListHeight: CGFloat = shouldUseSplitDropdownLayout ? 148 : 188
        let footballContentLevel = contextualFootballContentLevel
        let now = Date()

        VStack(alignment: .leading, spacing: 6) {
            if let footballMatch = item.footballMatch {
                HStack(spacing: 8) {
                    let concurrentFootballMatchCount = displayedContextualActionItems.count
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

                                if let scheduleText,
                                   !scheduleText.isEmpty {
                                    Text(scheduleText)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.trailing)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                        } else if let scheduleText,
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

                    contextualActionButtons(for: item, locationText: previewLocationText)
                }
            } else {
                if shouldShowDaylightPreview {
                    contextualDaylightHeader(for: item)
                } else {
                    rowPrimaryContent(for: item)

                    HStack {
                        Spacer(minLength: 0)
                        contextualActionButtons(for: item, locationText: previewLocationText)
                    }
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
                let concurrentFootballMatchCount = displayedContextualActionItems.count
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

    @ViewBuilder
    func contextualDaylightHeader(for item: UpcomingItem) -> some View {
        let accentColor = Color(nsColor: item.calendarColor)
        let titleFont = Font.system(size: 12, weight: .semibold)
        let timeFont = Font.system(size: 11, weight: .medium)

        HStack(alignment: .center, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                contextualMarkerView(for: item, accentColor: accentColor)

                Text(item.title)
                    .font(titleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            Spacer(minLength: 12)

            Text(timeText(item.date))
                .font(timeFont)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            contextualActionButtons(for: item, locationText: nil)
                .padding(.leading, 12)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func contextualMarkerView(for item: UpcomingItem, accentColor: Color) -> some View {
        if let markerSymbol = markerSymbolName(for: item) {
            Image(systemName: markerSymbol)
                .font(.system(size: 12, weight: .regular))
                .frame(width: 12, height: 12)
                .foregroundStyle(accentColor)
        } else if let image = markerImage(for: item) {
            let markerSize = markerImageSize(for: item)
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: markerSize.width, height: markerSize.height)
        } else {
            Capsule()
                .fill(accentColor)
                .frame(width: 4, height: 14)
        }
    }

    @ViewBuilder
    func contextualActionButtons(for item: UpcomingItem, locationText: String?) -> some View {
        HStack(spacing: 6) {
            Button {
                monitor.skipItem(item)
            } label: {
                Label("Skip", systemImage: "forward.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if let locationText {
                Button {
                    openMap(for: item, locationText: locationText)
                } label: {
                    Label("Map", systemImage: "map")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    func contextualDaylightPreview(for item: UpcomingItem, preferredHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Daylight Map")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            DaylightPreviewArtwork(
                latitude: settings.astronomyLatitude,
                longitude: settings.astronomyLongitude,
                date: item.date,
                isEnabled: hasValidAstronomyPreviewCoordinates
            )
            .frame(maxWidth: .infinity)
            .frame(height: preferredHeight)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    var hasValidAstronomyPreviewCoordinates: Bool {
        abs(settings.astronomyLatitude) <= 90 && abs(settings.astronomyLongitude) <= 180
    }
}
