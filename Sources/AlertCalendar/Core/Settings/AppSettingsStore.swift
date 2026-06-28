import Foundation

struct AppSettingsStore {
    let defaults: UserDefaults

    func registerDefaults() {
        removeLegacyFocusFilterDefaults()
        defaults.register(defaults: registrationDefaults)
    }

    func load() -> AppSettings {
        let defaultSettings = AppSettings.defaults
        let lookAheadHours = AppSettingsRules.normalizedDropdownWindowHours(
            defaults.integer(forKey: DefaultsKeys.lookAheadHours)
        )
        let storedSlackConnections = slackConnections()
        let storedSlackStatusSyncRules = slackStatusSyncRules(connections: storedSlackConnections)
        let effectiveSlackStatusSyncRules = storedSlackStatusSyncRules.isEmpty
            ? migratedLegacySlackStatusSyncRules(connections: storedSlackConnections)
            : storedSlackStatusSyncRules
        let legacySlackMeetingStatusText = SlackMeetingStatus.normalizedText(
            defaults.string(forKey: DefaultsKeys.slackMeetingStatusText)
        )
        let legacySlackMeetingStatusEmoji = SlackMeetingStatus.normalizedEmoji(
            defaults.string(forKey: DefaultsKeys.slackMeetingStatusEmoji)
        )
        let migratedSlackStatusSyncRules = effectiveSlackStatusSyncRules.map { rule in
            guard
                rule.statusText == SlackMeetingStatus.defaultText,
                rule.statusEmoji == SlackMeetingStatus.defaultEmoji,
                legacySlackMeetingStatusText != SlackMeetingStatus.defaultText ||
                    legacySlackMeetingStatusEmoji != SlackMeetingStatus.defaultEmoji
            else {
                return rule
            }

            var migratedRule = rule
            migratedRule.statusText = legacySlackMeetingStatusText
            migratedRule.statusEmoji = legacySlackMeetingStatusEmoji
            return migratedRule
        }

        return AppSettings(
            includeEvents: defaults.bool(forKey: DefaultsKeys.includeEvents),
            includeAllDayEvents: defaults.bool(forKey: DefaultsKeys.includeAllDayEvents),
            includeReminders: defaults.bool(forKey: DefaultsKeys.includeReminders),
            includeAstronomy: defaults.bool(forKey: DefaultsKeys.includeAstronomy),
            includeSunriseSunset: defaults.bool(forKey: DefaultsKeys.includeSunriseSunset),
            includeSolarNoonMidnight: defaults.bool(forKey: DefaultsKeys.includeSolarNoonMidnight),
            includeMoonPhases: defaults.bool(forKey: DefaultsKeys.includeMoonPhases),
            includeOrbitalHighlights: defaults.bool(forKey: DefaultsKeys.includeOrbitalHighlights),
            useAutomaticAstronomyLocation: defaults.bool(forKey: DefaultsKeys.useAutomaticAstronomyLocation),
            astronomyColorID: defaults.string(forKey: DefaultsKeys.astronomyColorID) ?? defaultSettings.astronomyColorID,
            astronomyLatitude: defaults.double(forKey: DefaultsKeys.astronomyLatitude),
            astronomyLongitude: defaults.double(forKey: DefaultsKeys.astronomyLongitude),
            selectedEventCalendarIDs: selectedCalendarIDs(for: .event),
            selectedReminderCalendarIDs: selectedCalendarIDs(for: .reminder),
            weekdayOnlyEventCalendarIDs: weekdayOnlyCalendarIDs(for: .event),
            weekdayOnlyReminderCalendarIDs: weekdayOnlyCalendarIDs(for: .reminder),
            lookAheadHours: lookAheadHours,
            contextualPreviewLeadMinutes: AppSettingsRules.normalizedContextualPreviewLeadMinutes(
                defaults.integer(forKey: DefaultsKeys.contextualPreviewLeadMinutes),
                dropdownWindowHours: lookAheadHours
            ),
            menuBarRotationWindowMinutes: AppSettingsRules.normalizedMenuBarRotationWindowMinutes(
                defaults.integer(forKey: DefaultsKeys.menuBarRotationWindowMinutes),
                dropdownWindowHours: lookAheadHours
            ),
            alertLeadMinutes: AppSettingsRules.normalizedAlertLeadMinutes(
                defaults.integer(forKey: DefaultsKeys.alertLeadMinutes)
            ),
            concurrentEventRotationSeconds: AppSettingsRules.normalizedConcurrentEventRotationSeconds(
                defaults.integer(forKey: DefaultsKeys.concurrentEventRotationSeconds)
            ),
            maxListItems: max(1, defaults.integer(forKey: DefaultsKeys.maxListItems)),
            enableBlinkAlert: defaults.bool(forKey: DefaultsKeys.enableBlinkAlert),
            menuBarFontSize: defaults.double(forKey: DefaultsKeys.menuBarFontSize),
            useSimplifiedCountdown: defaults.bool(forKey: DefaultsKeys.useSimplifiedCountdown),
            activeEventDisplayMode: ActiveEventDisplayMode(
                rawValue: defaults.string(forKey: DefaultsKeys.activeEventDisplayMode) ?? ""
            ) ?? defaultSettings.activeEventDisplayMode,
            useEventTitleEllipsis: defaults.bool(forKey: DefaultsKeys.useEventTitleEllipsis),
            eventTitleMaxCharacters: AppSettingsRules.normalizedEventTitleMaxCharacters(
                defaults.integer(forKey: DefaultsKeys.eventTitleMaxCharacters)
            ),
            footballTargetCalendarID: defaults.string(forKey: DefaultsKeys.footballTargetCalendarID) ?? defaultSettings.footballTargetCalendarID,
            footballCalendarAlertOption: FootballCalendarAlertOption(
                rawValue: defaults.string(forKey: DefaultsKeys.footballCalendarAlertOption) ?? ""
            ) ?? defaultSettings.footballCalendarAlertOption,
            enableFootballGoalNotifications: defaults.bool(forKey: DefaultsKeys.enableFootballGoalNotifications),
            includeFootballGoalScorerInNotifications: defaults.bool(forKey: DefaultsKeys.includeFootballGoalScorerInNotifications),
            enableFootballFinalNotifications: defaults.bool(forKey: DefaultsKeys.enableFootballFinalNotifications),
            enableFootballAutoAddNotifications: defaults.bool(forKey: DefaultsKeys.enableFootballAutoAddNotifications),
            showFinishedFootballMatches: defaults.bool(forKey: DefaultsKeys.showFinishedFootballMatches),
            finishedFootballMatchLookbackDays: AppSettingsRules.normalizedFootballWindowDays(
                defaults.integer(forKey: DefaultsKeys.finishedFootballMatchLookbackDays)
            ),
            footballMatchLookaheadDays: AppSettingsRules.normalizedFootballWindowDays(
                defaults.integer(forKey: DefaultsKeys.footballMatchLookaheadDays)
            ),
            slackConnections: storedSlackConnections,
            slackStatusSyncRules: migratedSlackStatusSyncRules,
            slackMeetingStatusText: legacySlackMeetingStatusText,
            slackMeetingStatusEmoji: legacySlackMeetingStatusEmoji,
            meetingBrowserRouting: meetingBrowserRoutingSettings()
        )
    }

    func save(_ settings: AppSettings) {
        defaults.set(settings.includeEvents, forKey: DefaultsKeys.includeEvents)
        defaults.set(settings.includeAllDayEvents, forKey: DefaultsKeys.includeAllDayEvents)
        defaults.set(settings.includeReminders, forKey: DefaultsKeys.includeReminders)
        defaults.set(settings.includeAstronomy, forKey: DefaultsKeys.includeAstronomy)
        defaults.set(settings.includeSunriseSunset, forKey: DefaultsKeys.includeSunriseSunset)
        defaults.set(settings.includeSolarNoonMidnight, forKey: DefaultsKeys.includeSolarNoonMidnight)
        defaults.set(settings.includeMoonPhases, forKey: DefaultsKeys.includeMoonPhases)
        defaults.set(settings.includeOrbitalHighlights, forKey: DefaultsKeys.includeOrbitalHighlights)
        defaults.set(settings.useAutomaticAstronomyLocation, forKey: DefaultsKeys.useAutomaticAstronomyLocation)
        defaults.set(settings.astronomyColorID, forKey: DefaultsKeys.astronomyColorID)
        defaults.set(AppSettingsRules.roundedCoordinate(settings.astronomyLatitude), forKey: DefaultsKeys.astronomyLatitude)
        defaults.set(AppSettingsRules.roundedCoordinate(settings.astronomyLongitude), forKey: DefaultsKeys.astronomyLongitude)
        defaults.set(Array(settings.selectedEventCalendarIDs).sorted(), forKey: DefaultsKeys.selectedEventCalendarIDs)
        defaults.set(Array(settings.selectedReminderCalendarIDs).sorted(), forKey: DefaultsKeys.selectedReminderCalendarIDs)
        defaults.set(Array(settings.weekdayOnlyEventCalendarIDs).sorted(), forKey: DefaultsKeys.weekdayOnlyEventCalendarIDs)
        defaults.set(Array(settings.weekdayOnlyReminderCalendarIDs).sorted(), forKey: DefaultsKeys.weekdayOnlyReminderCalendarIDs)
        defaults.set(AppSettingsRules.normalizedDropdownWindowHours(settings.lookAheadHours), forKey: DefaultsKeys.lookAheadHours)
        defaults.set(
            AppSettingsRules.normalizedContextualPreviewLeadMinutes(
                settings.contextualPreviewLeadMinutes,
                dropdownWindowHours: settings.lookAheadHours
            ),
            forKey: DefaultsKeys.contextualPreviewLeadMinutes
        )
        defaults.set(
            AppSettingsRules.normalizedMenuBarRotationWindowMinutes(
                settings.menuBarRotationWindowMinutes,
                dropdownWindowHours: settings.lookAheadHours
            ),
            forKey: DefaultsKeys.menuBarRotationWindowMinutes
        )
        defaults.set(AppSettingsRules.normalizedAlertLeadMinutes(settings.alertLeadMinutes), forKey: DefaultsKeys.alertLeadMinutes)
        defaults.set(
            AppSettingsRules.normalizedConcurrentEventRotationSeconds(settings.concurrentEventRotationSeconds),
            forKey: DefaultsKeys.concurrentEventRotationSeconds
        )
        defaults.set(max(1, settings.maxListItems), forKey: DefaultsKeys.maxListItems)
        defaults.set(settings.enableBlinkAlert, forKey: DefaultsKeys.enableBlinkAlert)
        defaults.set(settings.menuBarFontSize, forKey: DefaultsKeys.menuBarFontSize)
        defaults.set(settings.useSimplifiedCountdown, forKey: DefaultsKeys.useSimplifiedCountdown)
        defaults.set(settings.activeEventDisplayMode.rawValue, forKey: DefaultsKeys.activeEventDisplayMode)
        defaults.set(settings.useEventTitleEllipsis, forKey: DefaultsKeys.useEventTitleEllipsis)
        defaults.set(
            AppSettingsRules.normalizedEventTitleMaxCharacters(settings.eventTitleMaxCharacters),
            forKey: DefaultsKeys.eventTitleMaxCharacters
        )
        defaults.set(settings.footballTargetCalendarID, forKey: DefaultsKeys.footballTargetCalendarID)
        defaults.set(settings.footballCalendarAlertOption.rawValue, forKey: DefaultsKeys.footballCalendarAlertOption)
        defaults.set(settings.enableFootballGoalNotifications, forKey: DefaultsKeys.enableFootballGoalNotifications)
        defaults.set(settings.includeFootballGoalScorerInNotifications, forKey: DefaultsKeys.includeFootballGoalScorerInNotifications)
        defaults.set(settings.enableFootballFinalNotifications, forKey: DefaultsKeys.enableFootballFinalNotifications)
        defaults.set(settings.enableFootballAutoAddNotifications, forKey: DefaultsKeys.enableFootballAutoAddNotifications)
        defaults.set(settings.showFinishedFootballMatches, forKey: DefaultsKeys.showFinishedFootballMatches)
        defaults.set(
            AppSettingsRules.normalizedFootballWindowDays(settings.finishedFootballMatchLookbackDays),
            forKey: DefaultsKeys.finishedFootballMatchLookbackDays
        )
        defaults.set(
            AppSettingsRules.normalizedFootballWindowDays(settings.footballMatchLookaheadDays),
            forKey: DefaultsKeys.footballMatchLookaheadDays
        )
        defaults.set(
            SlackMeetingStatus.normalizedText(settings.slackMeetingStatusText),
            forKey: DefaultsKeys.slackMeetingStatusText
        )
        defaults.set(
            SlackMeetingStatus.normalizedEmoji(settings.slackMeetingStatusEmoji),
            forKey: DefaultsKeys.slackMeetingStatusEmoji
        )
        if let encodedSlackConnections = try? JSONEncoder().encode(
            SlackConnection.normalized(settings.slackConnections)
        ) {
            defaults.set(encodedSlackConnections, forKey: DefaultsKeys.slackConnections)
        }
        if let encodedSlackStatusSyncRules = try? JSONEncoder().encode(
            SlackStatusSyncRule.normalized(
                settings.slackStatusSyncRules,
                validConnectionIDs: Set(settings.slackConnections.map(\.id))
            )
        ) {
            defaults.set(encodedSlackStatusSyncRules, forKey: DefaultsKeys.slackStatusSyncRules)
        }
        if let encodedMeetingBrowserRouting = try? JSONEncoder().encode(
            settings.meetingBrowserRouting.normalized
        ) {
            defaults.set(encodedMeetingBrowserRouting, forKey: DefaultsKeys.meetingBrowserRouting)
        }

        // Clear the legacy single-rule keys once the new multi-rule settings are written.
        defaults.set(false, forKey: DefaultsKeys.enableSlackMeetingStatusSync)
        defaults.set("", forKey: DefaultsKeys.slackMeetingCalendarID)
        defaults.set("", forKey: DefaultsKeys.selectedSlackConnectionID)
    }

    func selectedCalendarIDs(for kind: CalendarItemKind) -> Set<String> {
        let key = kind == .event ? DefaultsKeys.selectedEventCalendarIDs : DefaultsKeys.selectedReminderCalendarIDs
        return Set(defaults.stringArray(forKey: key) ?? [])
    }

    func weekdayOnlyCalendarIDs(for kind: CalendarItemKind) -> Set<String> {
        let key = kind == .event ? DefaultsKeys.weekdayOnlyEventCalendarIDs : DefaultsKeys.weekdayOnlyReminderCalendarIDs
        return Set(defaults.stringArray(forKey: key) ?? [])
    }

    func slackConnections() -> [SlackConnection] {
        guard let data = defaults.data(forKey: DefaultsKeys.slackConnections) else { return [] }
        let decoded = (try? JSONDecoder().decode([SlackConnection].self, from: data)) ?? []
        return SlackConnection.normalized(decoded)
    }

    func slackStatusSyncRules(
        connections: [SlackConnection],
        availableCalendarIDs: Set<String>? = nil
    ) -> [SlackStatusSyncRule] {
        guard let data = defaults.data(forKey: DefaultsKeys.slackStatusSyncRules) else { return [] }
        let decoded = (try? JSONDecoder().decode([SlackStatusSyncRule].self, from: data)) ?? []
        return SlackStatusSyncRule.normalized(
            decoded,
            validConnectionIDs: Set(connections.map(\.id)),
            validCalendarIDs: availableCalendarIDs
        )
    }

    func meetingBrowserRoutingSettings(
        availableCalendarIDs: Set<String>? = nil
    ) -> MeetingBrowserRoutingSettings {
        guard let data = defaults.data(forKey: DefaultsKeys.meetingBrowserRouting) else {
            return .defaults
        }

        let decoded = (try? JSONDecoder().decode(MeetingBrowserRoutingSettings.self, from: data)) ?? .defaults
        return decoded.normalized(availableCalendarIDs: availableCalendarIDs)
    }

    private var registrationDefaults: [String: Any] {
        let defaultSettings = AppSettings.defaults

        return [
            DefaultsKeys.includeEvents: defaultSettings.includeEvents,
            DefaultsKeys.includeAllDayEvents: defaultSettings.includeAllDayEvents,
            DefaultsKeys.includeReminders: defaultSettings.includeReminders,
            DefaultsKeys.includeAstronomy: defaultSettings.includeAstronomy,
            DefaultsKeys.includeSunriseSunset: defaultSettings.includeSunriseSunset,
            DefaultsKeys.includeSolarNoonMidnight: defaultSettings.includeSolarNoonMidnight,
            DefaultsKeys.includeMoonPhases: defaultSettings.includeMoonPhases,
            DefaultsKeys.includeOrbitalHighlights: defaultSettings.includeOrbitalHighlights,
            DefaultsKeys.useAutomaticAstronomyLocation: defaultSettings.useAutomaticAstronomyLocation,
            DefaultsKeys.astronomyColorID: defaultSettings.astronomyColorID,
            DefaultsKeys.astronomyLatitude: defaultSettings.astronomyLatitude,
            DefaultsKeys.astronomyLongitude: defaultSettings.astronomyLongitude,
            DefaultsKeys.weekdayOnlyEventCalendarIDs: [],
            DefaultsKeys.weekdayOnlyReminderCalendarIDs: [],
            DefaultsKeys.lookAheadHours: defaultSettings.lookAheadHours,
            DefaultsKeys.contextualPreviewLeadMinutes: defaultSettings.contextualPreviewLeadMinutes,
            DefaultsKeys.menuBarRotationWindowMinutes: defaultSettings.menuBarRotationWindowMinutes,
            DefaultsKeys.alertLeadMinutes: defaultSettings.alertLeadMinutes,
            DefaultsKeys.concurrentEventRotationSeconds: defaultSettings.concurrentEventRotationSeconds,
            DefaultsKeys.maxListItems: defaultSettings.maxListItems,
            DefaultsKeys.enableBlinkAlert: defaultSettings.enableBlinkAlert,
            DefaultsKeys.useSimplifiedCountdown: defaultSettings.useSimplifiedCountdown,
            DefaultsKeys.activeEventDisplayMode: defaultSettings.activeEventDisplayMode.rawValue,
            DefaultsKeys.useEventTitleEllipsis: defaultSettings.useEventTitleEllipsis,
            DefaultsKeys.eventTitleMaxCharacters: defaultSettings.eventTitleMaxCharacters,
            DefaultsKeys.menuBarFontSize: defaultSettings.menuBarFontSize,
            DefaultsKeys.skippedItemKeys: [],
            DefaultsKeys.footballTargetCalendarID: defaultSettings.footballTargetCalendarID,
            DefaultsKeys.footballAutoAddCompetitionSlugs: [],
            DefaultsKeys.footballCalendarAlertOption: defaultSettings.footballCalendarAlertOption.rawValue,
            DefaultsKeys.enableFootballGoalNotifications: defaultSettings.enableFootballGoalNotifications,
            DefaultsKeys.includeFootballGoalScorerInNotifications: defaultSettings.includeFootballGoalScorerInNotifications,
            DefaultsKeys.enableFootballFinalNotifications: defaultSettings.enableFootballFinalNotifications,
            DefaultsKeys.enableFootballAutoAddNotifications: defaultSettings.enableFootballAutoAddNotifications,
            DefaultsKeys.showFinishedFootballMatches: defaultSettings.showFinishedFootballMatches,
            DefaultsKeys.finishedFootballMatchLookbackDays: defaultSettings.finishedFootballMatchLookbackDays,
            DefaultsKeys.footballMatchLookaheadDays: defaultSettings.footballMatchLookaheadDays,
            DefaultsKeys.slackMeetingStatusText: defaultSettings.slackMeetingStatusText,
            DefaultsKeys.slackMeetingStatusEmoji: defaultSettings.slackMeetingStatusEmoji,
            DefaultsKeys.meetingBrowserRouting: (try? JSONEncoder().encode(defaultSettings.meetingBrowserRouting)) ?? Data(),
            DefaultsKeys.didAutoRecoverEmptyEventCalendarSelection: false,
            DefaultsKeys.didAutoRecoverEmptyReminderCalendarSelection: false,
        ]
    }

    private func removeLegacyFocusFilterDefaults() {
        defaults.removeObject(forKey: "activeFocusCalendarFilterState")
    }

    private func migratedLegacySlackStatusSyncRules(
        connections: [SlackConnection]
    ) -> [SlackStatusSyncRule] {
        let selectedConnectionID = defaults.string(forKey: DefaultsKeys.selectedSlackConnectionID) ?? ""
        let selectedCalendarID = defaults.string(forKey: DefaultsKeys.slackMeetingCalendarID) ?? ""
        let isEnabled = defaults.bool(forKey: DefaultsKeys.enableSlackMeetingStatusSync)

        guard !selectedConnectionID.isEmpty, !selectedCalendarID.isEmpty else { return [] }

        return SlackStatusSyncRule.normalized(
            [
                SlackStatusSyncRule(
                    connectionID: selectedConnectionID,
                    calendarID: selectedCalendarID,
                    isEnabled: isEnabled
                ),
            ],
            validConnectionIDs: Set(connections.map(\.id))
        )
    }
}
