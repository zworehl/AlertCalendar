import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    @ViewBuilder
    func footballEventTextBlock(
        item: UpcomingItem,
        match: FootballFixtureMatch,
        accentColor: Color,
        titleColor: Color,
        titleFont: Font,
        detailFont: Font,
        detailIconFont: Font,
        detailTextColor: Color
    ) -> some View {
        footballFixtureHeadline(
            match: match,
            display: item.footballMenuBarDisplay,
            font: titleFont,
            titleColor: titleColor,
            showsCardBadges: false,
            showsStatusAccessories: false
        )

        if !item.isAllDay, let locationText = item.locationText {
            let locationName = displayLocationName(from: locationText)
            if shouldShowLocationRow(locationName: locationName, meetingURL: item.meetingURL) {
                HStack(alignment: .center, spacing: 4) {
                    Image(systemName: locationSymbolName(for: item))
                        .font(detailIconFont)
                        .frame(width: 12, height: 12, alignment: .center)
                        .foregroundStyle(accentColor)
                    Text(locationName)
                        .font(detailFont)
                        .foregroundStyle(detailTextColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    @ViewBuilder
    func footballCompetitionLine(
        match: FootballFixtureMatch,
        display: FootballMenuBarDisplay?,
        font: Font
    ) -> some View {
        HStack(alignment: .center, spacing: 4) {
            FootballCompetitionLogoView(
                localPath: display?.competitionLocalLogoPath,
                remoteURL: match.competitionLogoURL,
                placeholderSymbolSize: 11
            )

            Text(footballCompetitionDetailText(match: match, display: display))
                .font(font)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    func footballFixtureHeadline(
        match: FootballFixtureMatch,
        display: FootballMenuBarDisplay?,
        font: Font,
        titleColor: Color = .primary,
        showsScore: Bool = true,
        showsInlineAggregate: Bool = false,
        showsCardBadges: Bool,
        showsStatusAccessories: Bool
    ) -> some View {
        let accessories = FootballStatusAccessoriesView.accessories(for: match)

        HStack(alignment: .center, spacing: showsScore ? 6 : 10) {
            HStack(alignment: .center, spacing: showsScore ? 6 : 10) {
                footballTeamLabel(
                    abbreviation: display?.homeAbbreviation ?? FootballFixtureFormatter.teamDisplayIdentifier(for: match.homeTeam),
                    localLogoPath: display?.homeLocalLogoPath,
                    remoteLogoURL: FootballFixtureFormatter.isUnknownTeam(match.homeTeam) ? nil : match.homeTeam.logoURL,
                    isUnknown: FootballFixtureFormatter.isUnknownTeam(match.homeTeam),
                    usesCircularOutline: match.homeTeam.isNational,
                    logoLeading: false,
                    yellowCards: match.homeYellowCards,
                    redCards: match.homeRedCards,
                    showsCardBadges: showsCardBadges,
                    font: font,
                    titleColor: titleColor
                )

                if showsScore {
                    if match.hasVisibleScore {
                        HStack(spacing: 4) {
                            Text(FootballFixtureFormatter.scoreText(match.homeScore))
                                .frame(minWidth: 10, alignment: .center)

                            Text("-")
                                .foregroundStyle(.secondary)

                            Text(FootballFixtureFormatter.scoreText(match.awayScore))
                                .frame(minWidth: 10, alignment: .center)

                            if showsInlineAggregate,
                               let aggregateText = footballInlineAggregateText(for: match) {
                                Text(aggregateText)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        HStack(spacing: 4) {
                            Text("-")
                                .foregroundStyle(.secondary)

                            if showsInlineAggregate,
                               let aggregateText = footballInlineAggregateText(for: match) {
                                Text(aggregateText)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                footballTeamLabel(
                    abbreviation: display?.awayAbbreviation ?? FootballFixtureFormatter.teamDisplayIdentifier(for: match.awayTeam),
                    localLogoPath: display?.awayLocalLogoPath,
                    remoteLogoURL: FootballFixtureFormatter.isUnknownTeam(match.awayTeam) ? nil : match.awayTeam.logoURL,
                    isUnknown: FootballFixtureFormatter.isUnknownTeam(match.awayTeam),
                    usesCircularOutline: match.awayTeam.isNational,
                    logoLeading: true,
                    yellowCards: match.awayYellowCards,
                    redCards: match.awayRedCards,
                    showsCardBadges: showsCardBadges,
                    font: font,
                    titleColor: titleColor
                )
            }
            .fixedSize(horizontal: true, vertical: false)

            if showsStatusAccessories && accessories.hasAccessories {
                FootballStatusAccessoriesView(data: accessories)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .font(font)
        .foregroundStyle(titleColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    func footballTeamLabel(
        abbreviation: String,
        localLogoPath: String?,
        remoteLogoURL: URL?,
        isUnknown: Bool,
        usesCircularOutline: Bool,
        logoLeading: Bool,
        yellowCards: Int,
        redCards: Int,
        showsCardBadges: Bool,
        font: Font,
        titleColor: Color = .primary
    ) -> some View {
        HStack(spacing: 4) {
            if showsCardBadges && !logoLeading {
                footballCardBadges(yellowCards: yellowCards, redCards: redCards)
            }

            if logoLeading {
                FootballTeamLogoView(
                    localPath: localLogoPath,
                    remoteURL: remoteLogoURL,
                    isUnknown: isUnknown,
                    usesCircularOutline: usesCircularOutline,
                    circularOutlineColor: titleColor
                )
                Text(abbreviation)
                    .font(font)
            } else {
                Text(abbreviation)
                    .font(font)
                FootballTeamLogoView(
                    localPath: localLogoPath,
                    remoteURL: remoteLogoURL,
                    isUnknown: isUnknown,
                    usesCircularOutline: usesCircularOutline,
                    circularOutlineColor: titleColor
                )
            }

            if showsCardBadges && logoLeading {
                footballCardBadges(yellowCards: yellowCards, redCards: redCards)
            }
        }
    }

    @ViewBuilder
    func footballCardBadges(yellowCards: Int, redCards: Int) -> some View {
        if yellowCards > 0 || redCards > 0 {
            HStack(spacing: 3) {
                if yellowCards > 0 {
                    footballCardBadge(count: yellowCards, tint: Color(red: 0.95, green: 0.79, blue: 0.26))
                }
                if redCards > 0 {
                    footballCardBadge(count: redCards, tint: Color(red: 0.88, green: 0.24, blue: 0.21))
                }
            }
        }
    }

    func footballCardBadge(count: Int, tint: Color) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(tint)
                .frame(width: 7, height: 10)

            if count != 1 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    func footballCompetitionDetailText(match: FootballFixtureMatch, display: FootballMenuBarDisplay?) -> String {
        FootballFixtureFormatter.competitionDetailText(for: match, display: display)
    }

    func footballFixtureContextBadgeText(for match: FootballFixtureMatch) -> String? {
        FootballFixtureFormatter.fixtureContextText(for: match)
    }

    func footballInlineAggregateText(for match: FootballFixtureMatch) -> String? {
        FootballFixtureFormatter.menuBarAggregateText(for: match)
    }

    @ViewBuilder
    func footballFixtureContextBadge(for match: FootballFixtureMatch) -> some View {
        if let fixtureContext = footballFixtureContextBadgeText(for: match) {
            Text(fixtureContext)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    func locationSymbolName(for item: UpcomingItem) -> String {
        item.footballMatch == nil ? "mappin.circle" : FootballFixtureFormatter.footballLocationSymbolName
    }

    func footballContextualVenueName(for item: UpcomingItem, match: FootballFixtureMatch) -> String? {
        let rawLocation = item.locationText ?? match.locationText
        guard let rawLocation else { return nil }

        let locationName = displayLocationName(from: rawLocation)
        guard shouldShowLocationRow(locationName: locationName, meetingURL: item.meetingURL) else {
            return nil
        }

        return locationName
    }

    nonisolated static func footballContextualScheduleText(
        for match: FootballFixtureMatch,
        now: Date = AlertCalendarClock.nowRoundedToSecond(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String? {
        guard match.statusState == .scheduled, match.startDate > now, !match.hasInterruptedStatus else {
            return nil
        }

        return CalendarMonitor.footballScheduleText(
            for: match,
            now: now,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
    }

}
