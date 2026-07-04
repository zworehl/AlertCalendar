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
        settings.maxListItems = maxListItems
        settings.enableBlinkAlert = enableBlinkAlert
        settings.menuBarFontSize = menuBarFontSize
        settings.useSimplifiedCountdown = useSimplifiedCountdown
        settings.activeEventDisplayMode = activeEventDisplayMode
        settings.useEventTitleEllipsis = useEventTitleEllipsis
        settings.eventTitleMaxCharacters = eventTitleMaxCharacters
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
        settings.nonWorkingDateKeys = WorkingDayRules.normalizedNonWorkingDateKeys(nonWorkingDateKeys)
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
