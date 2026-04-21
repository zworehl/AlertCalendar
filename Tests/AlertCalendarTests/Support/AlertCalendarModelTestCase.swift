import AppKit
import Foundation
import XCTest
@testable import AlertCalendar

class AlertCalendarModelTestCase: XCTestCase {
    func makeUpcomingItem(id: String, title: String, startDate: Date, endDate: Date) -> UpcomingItem {
        UpcomingItem(
            id: id,
            title: title,
            date: startDate,
            endDate: endDate,
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: "Somewhere",
            meetingURL: nil,
            calendarID: "cal-1",
            calendarName: "Work",
            calendarColor: .systemBlue,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
    }
    func makeFootballMatch(
        id: String,
        startDate: Date,
        actualStartDate: Date?,
        statusState: FootballFixtureStatusState,
        statusText: String,
        homeScore: String = "0",
        awayScore: String = "0"
    ) -> FootballFixtureMatch {
        FootballTestData.friendlyMatch(
            id: id,
            startDate: startDate,
            actualStartDate: actualStartDate,
            statusState: statusState,
            statusText: statusText,
            locationText: "Mercedes-Benz Stadium, Atlanta, Georgia, USA",
            homeTeam: FootballTestData.nationalTeam(
                id: "home-\(id)",
                name: "United States",
                abbreviation: "USA",
                countryName: "United States"
            ),
            awayTeam: FootballTestData.nationalTeam(
                id: "away-\(id)",
                name: "Portugal",
                abbreviation: "POR",
                countryName: "Portugal"
            ),
            homeScore: homeScore,
            awayScore: awayScore
        )
    }
    func makeFootballUpcomingItem(_ match: FootballFixtureMatch) -> UpcomingItem {
        FootballTestData.upcomingFootballItem(
            for: match,
            endDate: match.startDate.addingTimeInterval(2 * 60 * 60)
        )
    }
}
