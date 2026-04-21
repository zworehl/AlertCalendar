import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    var hasUnsavedChanges: Bool {
        didLoad && draft != storedDraft()
    }

    func storedDraft() -> SettingsDraft {
        SettingsDraft(settings: monitor.settingsStore.load())
    }

    func resetDraft() {
        draft = storedDraft()
    }

    func synchronizeDraftWithStoredSettings(force: Bool = false) {
        guard force || (didLoad && !hasUnsavedChanges) else { return }
        resetDraft()
    }

    var availableEventCalendarSignature: [String] {
        availableEventCalendars.map(\.id)
    }

    var availableReminderCalendarSignature: [String] {
        availableReminderCalendars.map(\.id)
    }

    func synchronizeSettingsStateFromMonitor() {
        hasEventsAccess = monitor.hasEventsAccess
        hasRemindersAccess = monitor.hasRemindersAccess
        availableEventCalendars = monitor.availableEventCalendars
        availableReminderCalendars = monitor.availableReminderCalendars
        calendarAccessDescription = monitor.calendarAccessDescription
        astronomyLocationStatus = monitor.astronomyLocationStatus
        locationAuthorizationStatus = SettingsPermissionKind.currentLocationAuthorizationStatus()
        lastRefreshDate = monitor.lastRefreshDate
    }

    func applyDraft() {
        let oldAutoLocation = monitor.settingsStore.load().useAutomaticAstronomyLocation
        var settings = monitor.settingsStore.load()

        settings.includeEvents = draft.includeEvents
        settings.includeAllDayEvents = draft.includeAllDayEvents
        settings.includeReminders = draft.includeReminders
        settings.lookAheadHours = normalizedDropdownWindowHours(draft.lookAheadHours)
        settings.contextualPreviewLeadMinutes = normalizedContextualPreviewLeadMinutes(
            draft.contextualPreviewLeadMinutes,
            dropdownWindowHours: settings.lookAheadHours
        )
        settings.menuBarRotationWindowMinutes = normalizedMenuBarRotationWindowMinutes(
            draft.menuBarRotationWindowMinutes,
            dropdownWindowHours: settings.lookAheadHours
        )
        settings.alertLeadMinutes = draft.alertLeadMinutes
        settings.concurrentEventRotationSeconds = draft.concurrentEventRotationSeconds
        settings.maxListItems = draft.maxListItems
        settings.enableBlinkAlert = draft.enableBlinkAlert
        settings.menuBarFontSize = draft.menuBarFontSize
        settings.useSimplifiedCountdown = draft.useSimplifiedCountdown
        settings.activeEventDisplayMode = draft.activeEventDisplayMode
        settings.useEventTitleEllipsis = draft.useEventTitleEllipsis
        settings.eventTitleMaxCharacters = draft.eventTitleMaxCharacters
        settings.includeAstronomy = draft.includeAstronomy
        settings.includeSunriseSunset = draft.includeSunriseSunset
        settings.includeSolarNoonMidnight = draft.includeSolarNoonMidnight
        settings.includeMoonPhases = draft.includeMoonPhases
        settings.includeOrbitalHighlights = draft.includeOrbitalHighlights
        settings.useAutomaticAstronomyLocation = draft.useAutomaticAstronomyLocation
        settings.astronomyColorID = draft.astronomyColorID
        settings.astronomyLatitude = roundTo3Decimals(draft.astronomyLatitude)
        settings.astronomyLongitude = roundTo3Decimals(draft.astronomyLongitude)
        settings.selectedEventCalendarIDs = draft.selectedEventCalendarIDs
        settings.selectedReminderCalendarIDs = draft.selectedReminderCalendarIDs
        settings.weekdayOnlyEventCalendarIDs = draft.weekdayOnlyEventCalendarIDs
        settings.weekdayOnlyReminderCalendarIDs = draft.weekdayOnlyReminderCalendarIDs

        monitor.settingsStore.save(settings)

        if draft.useAutomaticAstronomyLocation, !oldAutoLocation {
            monitor.refreshAstronomyCoordinatesFromSystem()
        } else if !draft.useAutomaticAstronomyLocation {
            monitor.astronomyLocationStatus = "Manual coordinates"
            monitor.refreshNow()
        } else {
            monitor.refreshNow()
        }
    }

    func persistCalendarSelectionDraft() {
        var settings = monitor.settingsStore.load()
        settings.selectedEventCalendarIDs = draft.selectedEventCalendarIDs
        settings.selectedReminderCalendarIDs = draft.selectedReminderCalendarIDs
        settings.weekdayOnlyEventCalendarIDs = draft.weekdayOnlyEventCalendarIDs
        settings.weekdayOnlyReminderCalendarIDs = draft.weekdayOnlyReminderCalendarIDs
        monitor.settingsStore.save(settings)
        monitor.refreshNow()
    }

    func detectLocation() {
        Task { @MainActor in
            guard let coordinate = await monitor.detectAstronomyCoordinate() else { return }
            draft.astronomyLatitude = roundTo3Decimals(coordinate.latitude)
            draft.astronomyLongitude = roundTo3Decimals(coordinate.longitude)
        }
    }

    func roundTo3Decimals(_ value: Double) -> Double {
        AppSettingsRules.roundedCoordinate(value)
    }

    func normalizedDropdownWindowHours(_ value: Int) -> Int {
        AppSettingsRules.normalizedDropdownWindowHours(value)
    }

    func maximumMenuBarRotationWindowMinutes(dropdownWindowHours: Int) -> Int {
        Self.maximumMenuBarRotationWindowMinutes(dropdownWindowHours: dropdownWindowHours)
    }

    func maximumContextualPreviewLeadMinutes(dropdownWindowHours: Int) -> Int {
        Self.maximumContextualPreviewLeadMinutes(dropdownWindowHours: dropdownWindowHours)
    }

    func normalizedMenuBarRotationWindowMinutes(_ value: Int, dropdownWindowHours: Int) -> Int {
        Self.normalizedMenuBarRotationWindowMinutes(value, dropdownWindowHours: dropdownWindowHours)
    }

    func normalizedContextualPreviewLeadMinutes(_ value: Int, dropdownWindowHours: Int) -> Int {
        Self.normalizedContextualPreviewLeadMinutes(value, dropdownWindowHours: dropdownWindowHours)
    }

}
