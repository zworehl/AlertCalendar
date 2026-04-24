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
        SettingsDraft(settings: monitor.currentSettings)
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
        refreshDiagnostics = monitor.refreshDiagnostics
        slackConnections = monitor.slackConnections()
        slackConnectionStatusMessage = monitor.slackConnectionStatusMessage
        slackRuntimeStatusDescription = monitor.slackRuntimeStatusDescription
        syncSlackDraftSelectionIfNeeded()
    }

    func applyDraft() {
        let oldAutoLocation = monitor.currentSettings.useAutomaticAstronomyLocation
        var settings = monitor.currentSettings

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
        settings.astronomyLatitude = roundedCoordinate(draft.astronomyLatitude)
        settings.astronomyLongitude = roundedCoordinate(draft.astronomyLongitude)
        settings.selectedEventCalendarIDs = draft.selectedEventCalendarIDs
        settings.selectedReminderCalendarIDs = draft.selectedReminderCalendarIDs
        settings.weekdayOnlyEventCalendarIDs = draft.weekdayOnlyEventCalendarIDs
        settings.weekdayOnlyReminderCalendarIDs = draft.weekdayOnlyReminderCalendarIDs
        settings.slackMeetingStatusText = SlackMeetingStatus.normalizedText(draft.slackMeetingStatusText)
        settings.slackMeetingStatusEmoji = SlackMeetingStatus.normalizedEmoji(draft.slackMeetingStatusEmoji)
        settings.slackStatusSyncRules = SlackStatusSyncRule.normalized(
            draft.slackStatusSyncRules,
            validConnectionIDs: Set(settings.slackConnections.map(\.id)),
            validCalendarIDs: Set(availableEventCalendars.map(\.id))
        )

        monitor.persistSettings(settings)

        if draft.useAutomaticAstronomyLocation, !oldAutoLocation {
            monitor.refreshAstronomyCoordinatesFromSystem()
        } else if !draft.useAutomaticAstronomyLocation {
            monitor.astronomyLocationStatus = "Manual coordinates"
            monitor.refreshNow(reason: .settingsChanged)
        } else {
            monitor.refreshNow(reason: .settingsChanged)
        }
    }

    func persistCalendarSelectionDraft() {
        var settings = monitor.currentSettings
        settings.selectedEventCalendarIDs = draft.selectedEventCalendarIDs
        settings.selectedReminderCalendarIDs = draft.selectedReminderCalendarIDs
        settings.weekdayOnlyEventCalendarIDs = draft.weekdayOnlyEventCalendarIDs
        settings.weekdayOnlyReminderCalendarIDs = draft.weekdayOnlyReminderCalendarIDs
        monitor.persistSettings(settings)
        monitor.refreshNow(reason: .calendarSelectionChanged)
    }

    func detectLocation() {
        Task { @MainActor in
            guard let coordinate = await monitor.detectAstronomyCoordinate() else { return }
            draft.astronomyLatitude = roundedCoordinate(coordinate.latitude)
            draft.astronomyLongitude = roundedCoordinate(coordinate.longitude)
        }
    }

    func roundedCoordinate(_ value: Double) -> Double {
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

    func connectSlackToken() {
        let token = slackUserTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            slackConnectErrorMessage = "Paste a Slack user token first."
            return
        }

        slackConnectErrorMessage = nil

        Task { @MainActor in
            do {
                _ = try await monitor.connectSlackUserToken(token)
                slackUserTokenDraft = ""
                slackConnections = monitor.slackConnections()
                draft.slackStatusSyncRules = monitor.currentSettings.slackStatusSyncRules
                syncSlackDraftSelectionIfNeeded()
                slackConnectionStatusMessage = "Slack token connected."
                didAttemptSlackConnectionMetadataRefresh = false
                refreshSlackConnectionMetadataIfNeeded(force: true)
                monitor.refreshNow(reason: .slackConnectionChanged)
            } catch {
                slackConnectErrorMessage = error.localizedDescription
            }
        }
    }

    func extractSlackTokenFromClipboard() {
        guard let clipboardText = NSPasteboard.general.string(forType: .string),
              let token = SlackUserTokenExtractor.firstToken(in: clipboardText) else {
            slackConnectErrorMessage = "No Slack user token was found in the clipboard."
            return
        }

        slackUserTokenDraft = token
        slackConnectErrorMessage = nil
        slackConnectionStatusMessage = "Slack token extracted from the clipboard."
    }

    func openSlackAppDashboard() {
        guard let url = URL(string: "https://api.slack.com/apps") else { return }
        NSWorkspace.shared.open(url)
    }

    func removeSlackAccount(_ connection: SlackConnection) {
        Task { @MainActor in
            await monitor.removeSlackConnection(connection)
            slackConnections = monitor.slackConnections()
            draft.slackStatusSyncRules.removeAll { $0.connectionID == connection.id }
            syncSlackDraftSelectionIfNeeded()
        }
    }

    func preferredSlackMeetingCalendarID() -> String {
        if let selectedCalendar = availableEventCalendars.first(where: { draft.selectedEventCalendarIDs.contains($0.id) }) {
            return selectedCalendar.id
        }
        return availableEventCalendars.first?.id ?? ""
    }

    func addSlackStatusSyncRule() {
        guard
            let availablePair = firstAvailableSlackStatusSyncPair(
                preferredConnectionID: slackConnections.first?.id,
                preferredCalendarID: preferredSlackMeetingCalendarID()
            )
        else {
            return
        }

        draft.slackStatusSyncRules.append(
            SlackStatusSyncRule(
                connectionID: availablePair.connectionID,
                calendarID: availablePair.calendarID,
                isEnabled: false
            )
        )
        syncSlackDraftSelectionIfNeeded()
    }

    func removeSlackStatusSyncRule(_ ruleID: String) {
        draft.slackStatusSyncRules.removeAll { $0.id == ruleID }
    }

    func syncSlackDraftSelectionIfNeeded() {
        let orderedConnectionIDs = slackConnections.map(\.id)
        let orderedCalendarIDs = availableEventCalendars.map(\.id)
        let validConnectionIDs = Set(orderedConnectionIDs)
        let validCalendarIDs = Set(orderedCalendarIDs)
        let fallbackConnectionID = slackConnections.first?.id ?? ""
        let fallbackCalendarID = preferredSlackMeetingCalendarID()

        draft.slackStatusSyncRules = SlackStatusSyncRule.uniquelyResolved(
            draft.slackStatusSyncRules.map { rule in
                var updatedRule = rule

                if !validConnectionIDs.contains(updatedRule.connectionID) {
                    updatedRule.connectionID = fallbackConnectionID
                    updatedRule.isEnabled = false
                }

                if !validCalendarIDs.contains(updatedRule.calendarID) {
                    updatedRule.calendarID = fallbackCalendarID
                    updatedRule.isEnabled = false
                }

                return updatedRule
            },
            orderedConnectionIDs: orderedConnectionIDs,
            orderedCalendarIDs: orderedCalendarIDs
        )
    }

    func hasAvailableSlackStatusSyncPair(excludingRuleID: String? = nil) -> Bool {
        firstAvailableSlackStatusSyncPair(excludingRuleID: excludingRuleID) != nil
    }

    func slackStatusSyncUsedPairKeys(excludingRuleID: String? = nil) -> Set<String> {
        Set(
            draft.slackStatusSyncRules.compactMap { rule in
                guard rule.id != excludingRuleID else { return nil }
                guard
                    let connectionID = SlackConnection.normalizedValue(rule.connectionID),
                    let calendarID = SlackConnection.normalizedValue(rule.calendarID)
                else {
                    return nil
                }

                return SlackStatusSyncRule.pairKey(connectionID: connectionID, calendarID: calendarID)
            }
        )
    }

    func firstAvailableSlackStatusSyncPair(
        preferredConnectionID: String? = nil,
        preferredCalendarID: String? = nil,
        excludingRuleID: String? = nil
    ) -> (connectionID: String, calendarID: String)? {
        return SlackStatusSyncRule.firstAvailablePair(
            orderedConnectionIDs: slackConnections.map(\.id),
            orderedCalendarIDs: availableEventCalendars.map(\.id),
            usedPairKeys: slackStatusSyncUsedPairKeys(excludingRuleID: excludingRuleID),
            preferredConnectionID: preferredConnectionID,
            preferredCalendarID: preferredCalendarID
        )
    }

    func isSlackStatusSyncPairAvailable(
        connectionID: String,
        calendarID: String,
        excludingRuleID: String
    ) -> Bool {
        guard
            let normalizedConnectionID = SlackConnection.normalizedValue(connectionID),
            let normalizedCalendarID = SlackConnection.normalizedValue(calendarID)
        else {
            return false
        }

        let pairKey = SlackStatusSyncRule.pairKey(
            connectionID: normalizedConnectionID,
            calendarID: normalizedCalendarID
        )

        return !draft.slackStatusSyncRules.contains { rule in
            guard rule.id != excludingRuleID else { return false }
            guard
                let existingConnectionID = SlackConnection.normalizedValue(rule.connectionID),
                let existingCalendarID = SlackConnection.normalizedValue(rule.calendarID)
            else {
                return false
            }

            return SlackStatusSyncRule.pairKey(
                connectionID: existingConnectionID,
                calendarID: existingCalendarID
            ) == pairKey
        }
    }

    func isSlackStatusSyncPairAvailable(
        connectionID: String,
        calendarID: String,
        usedPairKeys: Set<String>
    ) -> Bool {
        guard
            let normalizedConnectionID = SlackConnection.normalizedValue(connectionID),
            let normalizedCalendarID = SlackConnection.normalizedValue(calendarID)
        else {
            return false
        }

        return !usedPairKeys.contains(
            SlackStatusSyncRule.pairKey(
                connectionID: normalizedConnectionID,
                calendarID: normalizedCalendarID
            )
        )
    }

    func updateSlackStatusSyncRuleConnection(_ connectionID: String, at index: Int) {
        guard draft.slackStatusSyncRules.indices.contains(index) else { return }

        let rule = draft.slackStatusSyncRules[index]
        guard let replacement = firstAvailableSlackStatusSyncPair(
            preferredConnectionID: connectionID,
            preferredCalendarID: rule.calendarID,
            excludingRuleID: rule.id
        ) else {
            return
        }

        draft.slackStatusSyncRules[index].connectionID = replacement.connectionID
        draft.slackStatusSyncRules[index].calendarID = replacement.calendarID
    }

    func updateSlackStatusSyncRuleCalendar(_ calendarID: String, at index: Int) {
        guard draft.slackStatusSyncRules.indices.contains(index) else { return }

        let rule = draft.slackStatusSyncRules[index]
        guard let replacement = firstAvailableSlackStatusSyncPair(
            preferredConnectionID: rule.connectionID,
            preferredCalendarID: calendarID,
            excludingRuleID: rule.id
        ) else {
            return
        }

        draft.slackStatusSyncRules[index].connectionID = replacement.connectionID
        draft.slackStatusSyncRules[index].calendarID = replacement.calendarID
    }

    func refreshSlackConnectionMetadataIfNeeded(force: Bool = false) {
        guard !isRefreshingSlackConnectionMetadata else { return }
        guard force || !didAttemptSlackConnectionMetadataRefresh else { return }

        let connectionsToRefresh = force
            ? slackConnections
            : slackConnections.filter {
                $0.profileImageURLString == nil || $0.workspaceImageURLString == nil
            }
        guard !connectionsToRefresh.isEmpty else {
            didAttemptSlackConnectionMetadataRefresh = true
            return
        }

        isRefreshingSlackConnectionMetadata = true
        didAttemptSlackConnectionMetadataRefresh = true

        Task { @MainActor in
            await monitor.refreshSlackConnectionMetadataIfNeeded(force: force)
            slackConnections = monitor.slackConnections()
            draft.slackStatusSyncRules = monitor.currentSettings.slackStatusSyncRules
            syncSlackDraftSelectionIfNeeded()
            slackConnectionStatusMessage = monitor.slackConnectionStatusMessage
            isRefreshingSlackConnectionMetadata = false
        }
    }

}
