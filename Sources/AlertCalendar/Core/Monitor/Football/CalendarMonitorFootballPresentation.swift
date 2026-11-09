import Foundation

extension CalendarMonitor {
    func refreshUpcomingFootballItems(now: Date) {
        // A football heartbeat does not reload EventKit. Publish the new match
        // into the existing items so the menu does not wait for a calendar change.
        let refreshedItems = upcomingItems.map { item in
            guard let matchID = item.footballMatch?.id,
                  let match = footballMatchesByID[matchID] else { return item }
            return Self.footballItem(
                item, updatingWith: match,
                menuBarDisplay: footballMenuBarDisplay(for: match), now: now
            )
        }.sorted { UpcomingItem.sortPrecedes($0, $1) }
        if upcomingItems != refreshedItems {
            upcomingItems = refreshedItems
        }
    }

    nonisolated static func footballItem(
        _ item: UpcomingItem,
        updatingWith match: FootballFixtureMatch,
        menuBarDisplay: FootballMenuBarDisplay,
        now: Date
    ) -> UpcomingItem {
        let locationText = FootballCalendarLocation.resolvedText(
            reported: match.locationText, existing: item.locationText, structuredTitle: nil
        )
        return UpcomingItem(
            id: item.id,
            title: FootballFixtureFormatter.calendarTitle(for: match),
            date: footballEffectiveStartDate(for: match),
            endDate: approximateFootballMatchEndDate(for: match, now: now),
            isAllDay: item.isAllDay,
            hasExplicitTime: item.hasExplicitTime,
            showsMutedBackground: item.showsMutedBackground,
            travelTimeMinutes: item.travelTimeMinutes,
            locationText: locationText,
            locationCoordinate: locationText == item.locationText ? item.locationCoordinate : nil,
            meetingURL: item.meetingURL,
            openLinkURL: item.openLinkURL,
            urlCount: item.urlCount,
            urlHosts: item.urlHosts,
            agendaSummaryURLCandidates: item.agendaSummaryURLCandidates,
            agendaSummaryAttachments: item.agendaSummaryAttachments,
            organizer: item.organizer,
            attendees: item.attendees,
            eventParticipationStatus: item.eventParticipationStatus,
            isRecurring: item.isRecurring,
            hasDocumentIndicator: item.hasDocumentIndicator,
            descriptionText: item.descriptionText,
            lastModifiedAt: item.lastModifiedAt,
            calendarID: item.calendarID,
            calendarName: item.calendarName,
            calendarColor: item.calendarColor,
            kind: item.kind,
            gameStore: item.gameStore,
            footballMatch: match,
            footballMenuBarDisplay: menuBarDisplay
        )
    }
}
