import Foundation

extension SettingsDraft {
    func applied(
        to currentSettings: AppSettings,
        availableEventCalendarIDs: Set<String>
    ) -> AppSettings {
        var settings = currentSettings

        settings.includeEvents = includeEvents
        settings.includeAllDayEvents = includeAllDayEvents
        settings.includeReminders = includeReminders
        settings.lookAheadHours = AppSettingsRules.normalizedDropdownWindowHours(lookAheadHours)
        settings.contextualPreviewLeadMinutes = AppSettingsRules.normalizedContextualPreviewLeadMinutes(
            contextualPreviewLeadMinutes,
            dropdownWindowHours: settings.lookAheadHours
        )
        settings.menuBarRotationWindowMinutes = AppSettingsRules.normalizedMenuBarRotationWindowMinutes(
            menuBarRotationWindowMinutes,
            dropdownWindowHours: settings.lookAheadHours
        )
        settings.alertLeadMinutes = alertLeadMinutes
        settings.concurrentEventRotationSeconds = concurrentEventRotationSeconds
        settings.maxListItems = AppSettingsRules.normalizedMaximumDropdownItems(maxListItems)
        settings.showAgendaSummary = showAgendaSummary
        settings.agendaSummaryMaximumWords = AppSettingsRules.normalizedAgendaSummaryMaximumWords(
            agendaSummaryMaximumWords
        )
        settings.useLinkedPagePreviewsInAgendaSummary = useLinkedPagePreviewsInAgendaSummary
        settings.enableBlinkAlert = enableBlinkAlert
        settings.menuBarFontSize = menuBarFontSize
        settings.useSimplifiedCountdown = useSimplifiedCountdown
        settings.activeEventDisplayMode = activeEventDisplayMode
        settings.useEventTitleEllipsis = useEventTitleEllipsis
        settings.eventTitleMaxCharacters = eventTitleMaxCharacters
        settings.rewriteEventTitlesWithAppleIntelligence = rewriteEventTitlesWithAppleIntelligence
        settings.useRewrittenEventTitlesInDropdown = useRewrittenEventTitlesInDropdown
        settings.includeAstronomy = includeAstronomy
        settings.includeSunriseSunset = includeSunriseSunset
        settings.includeSolarNoonMidnight = includeSolarNoonMidnight
        settings.includeMoonPhases = includeMoonPhases
        settings.includeOrbitalHighlights = includeOrbitalHighlights
        settings.useAutomaticAstronomyLocation = useAutomaticAstronomyLocation
        settings.astronomyColorID = astronomyColorID
        settings.astronomyLatitude = AppSettingsRules.roundedCoordinate(astronomyLatitude)
        settings.astronomyLongitude = AppSettingsRules.roundedCoordinate(astronomyLongitude)
        settings.selectedEventCalendarIDs = selectedEventCalendarIDs
        settings.selectedReminderCalendarIDs = selectedReminderCalendarIDs
        settings.weekdayOnlyEventCalendarIDs = weekdayOnlyEventCalendarIDs
        settings.weekdayOnlyReminderCalendarIDs = weekdayOnlyReminderCalendarIDs
        settings.calendarAlertRules = CalendarAlertRule.normalized(
            calendarAlertRules,
            validCalendarIDs: availableEventCalendarIDs
        )
        settings.nonWorkingDateKeys = WorkingDayRules.normalizedNonWorkingDateKeys(nonWorkingDateKeys)
        settings.footballTargetCalendarID = footballTargetCalendarID
        settings.footballAutoAddCompetitionSlugs = Set(
            CalendarMonitor.normalizedFootballAutoAddCompetitionSlugs(
                Array(footballAutoAddCompetitionSlugs)
            )
        )
        settings.footballCalendarAlertOption = footballCalendarAlertOption
        settings.enableFootballGoalNotifications = enableFootballGoalNotifications
        settings.enableFootballDisallowedGoalNotifications = enableFootballDisallowedGoalNotifications
        settings.includeFootballGoalScorerInNotifications = includeFootballGoalScorerInNotifications
        settings.enableFootballFinalNotifications = enableFootballFinalNotifications
        settings.enableFootballAutoAddNotifications = enableFootballAutoAddNotifications
        settings.showFinishedFootballMatches = showFinishedFootballMatches
        settings.finishedFootballMatchLookbackDays = AppSettingsRules.normalizedFootballWindowDays(
            finishedFootballMatchLookbackDays
        )
        settings.footballMatchLookaheadDays = AppSettingsRules.normalizedFootballWindowDays(
            footballMatchLookaheadDays
        )
        settings.gameSaleTargetCalendarID = gameSaleTargetCalendarID
        settings.gameSaleCalendarAlertOption = gameSaleCalendarAlertOption
        settings.gameSaleAutoAddStores = gameSaleAutoAddStores
        settings.enableGameSaleAutoAddNotifications = enableGameSaleAutoAddNotifications
        settings.googleHolidayCountryIDs = GoogleHolidayCountry.normalizedCountryIDs(googleHolidayCountryIDs)
        settings.googleHolidayTargetCalendarID = googleHolidayTargetCalendarID
        settings.slackMeetingStatusText = SlackMeetingStatus.normalizedText(slackMeetingStatusText)
        settings.slackMeetingStatusEmoji = SlackMeetingStatus.normalizedEmoji(slackMeetingStatusEmoji)
        settings.slackStatusSyncRules = SlackStatusSyncRule.normalized(
            slackStatusSyncRules,
            validConnectionIDs: Set(settings.slackConnections.map(\.id)),
            validCalendarIDs: availableEventCalendarIDs
        )
        settings.meetingBrowserRouting = meetingBrowserRouting.normalized(
            availableCalendarIDs: availableEventCalendarIDs
        )

        return settings
    }
}
