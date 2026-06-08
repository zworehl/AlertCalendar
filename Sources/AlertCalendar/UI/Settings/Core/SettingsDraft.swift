import Foundation

struct SettingsDraft: Equatable {
    var includeEvents: Bool
    var includeAllDayEvents: Bool
    var includeReminders: Bool
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
    var slackStatusSyncRules: [SlackStatusSyncRule]
    var slackMeetingStatusText: String
    var slackMeetingStatusEmoji: String
    var meetingBrowserRouting: MeetingBrowserRoutingSettings

    init(settings: AppSettings) {
        includeEvents = settings.includeEvents
        includeAllDayEvents = settings.includeAllDayEvents
        includeReminders = settings.includeReminders
        lookAheadHours = settings.lookAheadHours
        contextualPreviewLeadMinutes = settings.contextualPreviewLeadMinutes
        menuBarRotationWindowMinutes = settings.menuBarRotationWindowMinutes
        alertLeadMinutes = settings.alertLeadMinutes
        concurrentEventRotationSeconds = settings.concurrentEventRotationSeconds
        maxListItems = settings.maxListItems
        enableBlinkAlert = settings.enableBlinkAlert
        menuBarFontSize = settings.menuBarFontSize
        useSimplifiedCountdown = settings.useSimplifiedCountdown
        activeEventDisplayMode = settings.activeEventDisplayMode
        useEventTitleEllipsis = settings.useEventTitleEllipsis
        eventTitleMaxCharacters = settings.eventTitleMaxCharacters
        includeAstronomy = settings.includeAstronomy
        includeSunriseSunset = settings.includeSunriseSunset
        includeSolarNoonMidnight = settings.includeSolarNoonMidnight
        includeMoonPhases = settings.includeMoonPhases
        includeOrbitalHighlights = settings.includeOrbitalHighlights
        useAutomaticAstronomyLocation = settings.useAutomaticAstronomyLocation
        astronomyColorID = settings.astronomyColorID
        astronomyLatitude = settings.astronomyLatitude
        astronomyLongitude = settings.astronomyLongitude
        selectedEventCalendarIDs = settings.selectedEventCalendarIDs
        selectedReminderCalendarIDs = settings.selectedReminderCalendarIDs
        weekdayOnlyEventCalendarIDs = settings.weekdayOnlyEventCalendarIDs
        weekdayOnlyReminderCalendarIDs = settings.weekdayOnlyReminderCalendarIDs
        slackStatusSyncRules = settings.slackStatusSyncRules
        slackMeetingStatusText = settings.slackMeetingStatusText
        slackMeetingStatusEmoji = settings.slackMeetingStatusEmoji
        meetingBrowserRouting = settings.meetingBrowserRouting
    }

    static let empty = SettingsDraft(settings: .defaults)
}
