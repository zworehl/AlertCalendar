import Foundation

struct AppSettings: Equatable {
    var includeEvents: Bool
    var includeAllDayEvents: Bool
    var includeReminders: Bool
    var includeAstronomy: Bool
    var includeSunriseSunset: Bool
    var includeSolarNoonMidnight: Bool
    var includeMoonPhases: Bool
    var includeOrbitalHighlights: Bool
    var useAutomaticAstronomyLocation: Bool
    var astronomyColorID: String
    var astronomyLatitude: Double
    var astronomyLongitude: Double
    var selectedEventCalendarIDs: Set<String>
    var selectedReminderCalendarIDs: Set<String>
    var weekdayOnlyEventCalendarIDs: Set<String>
    var weekdayOnlyReminderCalendarIDs: Set<String>
    var lookAheadHours: Int
    var contextualPreviewLeadMinutes: Int
    var menuBarRotationWindowMinutes: Int
    var alertLeadMinutes: Int
    var concurrentEventRotationSeconds: Int
    var maxListItems: Int
    var enableBlinkAlert: Bool
    var menuBarFontSize: Double
    var useSimplifiedCountdown: Bool
    var activeEventDisplayMode: ActiveEventDisplayMode
    var useEventTitleEllipsis: Bool
    var eventTitleMaxCharacters: Int
    var footballTargetCalendarID: String
    var footballCalendarAlertOption: FootballCalendarAlertOption
    var showFinishedFootballMatches: Bool
    var finishedFootballMatchLookbackDays: Int
    var footballMatchLookaheadDays: Int
    var slackConnections: [SlackConnection]
    var slackStatusSyncRules: [SlackStatusSyncRule]
    var slackMeetingStatusText: String
    var slackMeetingStatusEmoji: String
    var meetingBrowserRouting: MeetingBrowserRoutingSettings

    var includesAnyAstronomy: Bool {
        includeAstronomy && (
            includeSunriseSunset ||
            includeSolarNoonMidnight ||
            includeMoonPhases ||
            includeOrbitalHighlights
        )
    }

    func includes(moment: AstronomyMoment) -> Bool {
        guard includeAstronomy else { return false }

        switch moment {
        case .sunrise, .sunset:
            return includeSunriseSunset
        case .solarNoon, .solarMidnight:
            return includeSolarNoonMidnight
        case .newMoon, .waxingCrescent, .firstQuarter, .waxingGibbous, .fullMoon, .waningGibbous, .lastQuarter, .waningCrescent:
            return includeMoonPhases
        case .perihelion, .aphelion, .marchEquinox, .juneSolstice, .septemberEquinox, .decemberSolstice:
            return includeOrbitalHighlights
        }
    }

    static let defaults = AppSettings(
        includeEvents: true,
        includeAllDayEvents: true,
        includeReminders: true,
        includeAstronomy: true,
        includeSunriseSunset: true,
        includeSolarNoonMidnight: true,
        includeMoonPhases: true,
        includeOrbitalHighlights: true,
        useAutomaticAstronomyLocation: false,
        astronomyColorID: "blue",
        astronomyLatitude: 18.4655,
        astronomyLongitude: -66.1057,
        selectedEventCalendarIDs: [],
        selectedReminderCalendarIDs: [],
        weekdayOnlyEventCalendarIDs: [],
        weekdayOnlyReminderCalendarIDs: [],
        lookAheadHours: 24,
        contextualPreviewLeadMinutes: 120,
        menuBarRotationWindowMinutes: 60,
        alertLeadMinutes: 5,
        concurrentEventRotationSeconds: 30,
        maxListItems: 8,
        enableBlinkAlert: true,
        menuBarFontSize: 13.0,
        useSimplifiedCountdown: true,
        activeEventDisplayMode: .remaining,
        useEventTitleEllipsis: true,
        eventTitleMaxCharacters: 22,
        footballTargetCalendarID: "",
        footballCalendarAlertOption: .none,
        showFinishedFootballMatches: true,
        finishedFootballMatchLookbackDays: 7,
        footballMatchLookaheadDays: 14,
        slackConnections: [],
        slackStatusSyncRules: [],
        slackMeetingStatusText: SlackMeetingStatus.defaultText,
        slackMeetingStatusEmoji: SlackMeetingStatus.defaultEmoji,
        meetingBrowserRouting: .defaults
    )
}
