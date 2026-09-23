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
    var calendarAlertRules: [CalendarAlertRule]
    var lookAheadHours: Int
    var contextualPreviewLeadMinutes: Int
    var menuBarRotationWindowMinutes: Int
    var focusMenuBarOnActiveEvents: Bool
    var alertLeadMinutes: Int
    var concurrentEventRotationSeconds: Int
    var maxListItems: Int
    var showAgendaSummary: Bool
    var agendaSummaryMaximumWords: Int
    var useLinkedPagePreviewsInAgendaSummary: Bool
    var enableBlinkAlert: Bool
    var menuBarFontSize: Double
    var useSimplifiedCountdown: Bool
    var activeEventDisplayMode: ActiveEventDisplayMode
    var useEventTitleEllipsis: Bool
    var eventTitleMaxCharacters: Int
    var rewriteEventTitlesWithAppleIntelligence: Bool
    var useRewrittenEventTitlesInDropdown: Bool
    var useMailContextForEventTitleRewrite: Bool
    var footballTargetCalendarID: String
    var footballAutoAddCompetitionSlugs: Set<String>
    var footballCalendarAlertOption: FootballCalendarAlertOption
    var enableFootballGoalNotifications: Bool
    var enableFootballDisallowedGoalNotifications: Bool
    var includeFootballGoalScorerInNotifications: Bool
    var enableFootballFinalNotifications: Bool
    var enableFootballAutoAddNotifications: Bool
    var finishedFootballMatchLookbackDays: Int
    var footballMatchLookaheadDays: Int
    var gameSaleTargetCalendarID: String
    var gameSaleCalendarAlertOption: GameSaleCalendarAlertOption
    var gameSaleAutoAddStores: Set<GameStore>
    var enableGameSaleAutoAddNotifications: Bool
    var googleHolidayCountryIDs: Set<String>
    var googleHolidayTargetCalendarID: String
    var slackConnections: [SlackConnection]
    var slackStatusSyncRules: [SlackStatusSyncRule]
    var appleMusicStatus: AppleMusicStatusSettings
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
        calendarAlertRules: [],
        lookAheadHours: AppSettingsRules.defaultDropdownWindowHours,
        contextualPreviewLeadMinutes: 120,
        menuBarRotationWindowMinutes: 60,
        focusMenuBarOnActiveEvents: false,
        alertLeadMinutes: 5,
        concurrentEventRotationSeconds: 30,
        maxListItems: AppSettingsRules.defaultMaximumDropdownItems,
        showAgendaSummary: true,
        agendaSummaryMaximumWords: AppSettingsRules.defaultAgendaSummaryMaximumWords,
        useLinkedPagePreviewsInAgendaSummary: false,
        enableBlinkAlert: true,
        menuBarFontSize: 13.0,
        useSimplifiedCountdown: true,
        activeEventDisplayMode: .remaining,
        useEventTitleEllipsis: true,
        eventTitleMaxCharacters: 22,
        rewriteEventTitlesWithAppleIntelligence: false,
        useRewrittenEventTitlesInDropdown: false,
        useMailContextForEventTitleRewrite: false,
        footballTargetCalendarID: "",
        footballAutoAddCompetitionSlugs: [],
        footballCalendarAlertOption: .none,
        enableFootballGoalNotifications: true,
        enableFootballDisallowedGoalNotifications: true,
        includeFootballGoalScorerInNotifications: true,
        enableFootballFinalNotifications: true,
        enableFootballAutoAddNotifications: true,
        finishedFootballMatchLookbackDays: 7,
        footballMatchLookaheadDays: 14,
        gameSaleTargetCalendarID: "",
        gameSaleCalendarAlertOption: .fifteenMinutesBefore,
        gameSaleAutoAddStores: [],
        enableGameSaleAutoAddNotifications: true,
        googleHolidayCountryIDs: [],
        googleHolidayTargetCalendarID: "",
        slackConnections: [],
        slackStatusSyncRules: [],
        appleMusicStatus: AppleMusicStatusSettings(),
        slackMeetingStatusText: SlackMeetingStatus.defaultText,
        slackMeetingStatusEmoji: SlackMeetingStatus.defaultEmoji,
        meetingBrowserRouting: .defaults
    )
}
