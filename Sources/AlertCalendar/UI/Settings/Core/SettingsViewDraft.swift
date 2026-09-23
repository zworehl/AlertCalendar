import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    var hasUnsavedChanges: Bool {
        didLoad && (draft != storedDraft() || !pendingChanges.isEmpty)
    }

    func storedDraft() -> SettingsDraft {
        SettingsDraft(settings: monitor.currentSettings)
    }

    func resetDraft() {
        draft = storedDraft()
        pendingChanges = SettingsPendingChanges()
        slackConnections = monitor.slackConnections()
        syncSlackDraftSelectionIfNeeded()
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

    var meetingBrowserProfilesByBrowser: [MeetingBrowserKind: [MeetingBrowserProfileOption]] {
        meetingBrowserProfileCatalog.profilesByBrowser
    }

    var meetingBrowserProfileIssuesByBrowser: [MeetingBrowserKind: MeetingBrowserProfileLoadIssue] {
        meetingBrowserProfileCatalog.issuesByBrowser
    }

    var meetingBrowserProfileIssues: [MeetingBrowserProfileLoadIssue] {
        meetingBrowserProfileIssuesByBrowser.values.sorted {
            $0.browser.title.localizedCaseInsensitiveCompare($1.browser.title) == .orderedAscending
        }
    }

    func refreshMeetingBrowserProfiles() {
        let installedBrowsers = MeetingBrowserCatalog.installedBrowsers()
        installedMeetingBrowsers = installedBrowsers
        meetingBrowserProfileCatalog = MeetingBrowserProfileStore.catalog(for: installedBrowsers)
    }

    func synchronizeSettingsStateFromMonitor(refreshBrowserProfiles: Bool = false) {
        hasEventsAccess = monitor.hasEventsAccess
        hasRemindersAccess = monitor.hasRemindersAccess
        availableEventCalendars = monitor.availableEventCalendars
        availableReminderCalendars = monitor.availableReminderCalendars
        calendarAccessDescription = monitor.calendarAccessDescription
        calendarAlertRuleStatusDescription = monitor.calendarAlertRuleStatusDescription
        astronomyLocationStatus = monitor.astronomyLocationStatus
        eventAuthorizationStatus = SettingsPermissionKind.currentEventAuthorizationStatus()
        reminderAuthorizationStatus = SettingsPermissionKind.currentReminderAuthorizationStatus()
        locationAuthorizationStatus = SettingsPermissionKind.currentLocationAuthorizationStatus()
        contactsAuthorizationStatus = SettingsPermissionKind.currentContactsAuthorizationStatus()
        mailAutomationAuthorizationStatus = AppleMailAutomationPermission.currentStatus()
        lastRefreshDate = monitor.lastRefreshDate
        lastGameSalesRefreshDate = monitor.lastGameSalesRefreshDate
        googleHolidayLastRefreshDate = monitor.googleHolidayLastRefreshDate
        lastFootballRefreshDate = monitor.lastFootballRefreshDate
        lastAstronomyLocationRefreshDate = monitor.lastAstronomyLocationRefreshDate
        lastSlackStatusSyncDate = monitor.lastSlackStatusSyncDate
        refreshDiagnostics = monitor.refreshDiagnostics
        externalFeedDiagnostics = monitor.externalFeedDiagnostics
        slackConnections = monitor.slackConnections().filter {
            pendingChanges.slackConnectionsToRemove[$0.id] == nil
        }
        slackConnectionStatusMessage = monitor.slackConnectionStatusMessage
        slackRuntimeStatusDescription = monitor.slackRuntimeStatusDescription
        if refreshBrowserProfiles {
            refreshMeetingBrowserProfiles()
        }
        syncSlackDraftSelectionIfNeeded()
    }

    func applyDraft() {
        guard hasUnsavedChanges, !isApplyingChanges else { return }

        let previousSettings = monitor.currentSettings
        let oldAutoLocation = previousSettings.useAutomaticAstronomyLocation
        let stagedChanges = pendingChanges
        let settings = draft.applied(
            to: previousSettings,
            availableEventCalendarIDs: Set(availableEventCalendars.map(\.id))
        )
        let footballConfigurationChanged = settings.footballTargetCalendarID != previousSettings.footballTargetCalendarID
            || settings.footballAutoAddCompetitionSlugs != previousSettings.footballAutoAddCompetitionSlugs
            || settings.footballCalendarAlertOption != previousSettings.footballCalendarAlertOption
        let gameSaleConfigurationChanged = settings.gameSaleTargetCalendarID != previousSettings.gameSaleTargetCalendarID
            || settings.gameSaleAutoAddStores != previousSettings.gameSaleAutoAddStores
            || settings.gameSaleCalendarAlertOption != previousSettings.gameSaleCalendarAlertOption
        let googleHolidayConfigurationChanged = settings.googleHolidayTargetCalendarID
                != previousSettings.googleHolidayTargetCalendarID
            || settings.googleHolidayCountryIDs != previousSettings.googleHolidayCountryIDs

        if settings != previousSettings {
            monitor.persistSettings(settings)
        }
        draft = SettingsDraft(settings: settings)
        pendingChanges = SettingsPendingChanges()
        isApplyingChanges = true
        settingsWindowCloseGuard.hasUnsavedChanges = false

        if footballConfigurationChanged {
            let now = AlertCalendarClock.nowRoundedToSecond()
            monitor.applyManagedFootballAlertConfigurationIfNeeded(now: now)
        }

        if gameSaleConfigurationChanged {
            monitor.applyManagedGameSaleAlertConfiguration()
        }

        if draft.useAutomaticAstronomyLocation, !oldAutoLocation {
            monitor.refreshAstronomyCoordinatesFromSystem()
        } else if !draft.useAutomaticAstronomyLocation {
            monitor.astronomyLocationStatus = "Manual coordinates"
            monitor.refreshNow(reason: .settingsChanged)
        } else {
            monitor.refreshNow(reason: .settingsChanged)
        }

        Task { @MainActor in
            if footballConfigurationChanged {
                let now = AlertCalendarClock.nowRoundedToSecond()
                await monitor.syncAutoAddedFootballMatchesIfNeeded(now: now, force: true)
                await monitor.syncManagedFootballEventsIfNeeded(now: now, force: true)
            }

            if gameSaleConfigurationChanged {
                await monitor.refreshGameSales(forceRefresh: true)
            }

            if googleHolidayConfigurationChanged {
                await Task.yield()
                await monitor.refreshGoogleHolidays(forceRefresh: true)
            }

            await applyPendingContentChanges(stagedChanges)
            isApplyingChanges = false
        }
    }

    func applyPendingContentChanges(_ stagedChanges: SettingsPendingChanges) async {
        let footballChanges = stagedChanges.footballFixtures.values.sorted {
            if $0.item.startDate != $1.item.startDate {
                return $0.item.startDate < $1.item.startDate
            }
            return $0.item.id < $1.item.id
        }
        for change in footballChanges {
            switch change.mutation {
            case .add:
                _ = await monitor.addFootballMatchToCalendar(change.item)
            case .remove:
                monitor.removeFootballMatchFromCalendar(change.item)
            }
        }

        let gameSaleChanges = stagedChanges.gameSales.values.sorted {
            if $0.item.startDate != $1.item.startDate {
                return $0.item.startDate < $1.item.startDate
            }
            return $0.item.id < $1.item.id
        }
        for change in gameSaleChanges {
            switch change.mutation {
            case .add:
                _ = await monitor.addGameSaleToCalendar(change.item)
            case .remove:
                monitor.removeGameSaleFromCalendar(change.item)
            }
        }

        for connection in stagedChanges.slackConnectionsToRemove.values.sorted(by: { $0.id < $1.id }) {
            await monitor.removeSlackConnection(connection)
        }

        var failedSlackTokens: [String] = []
        for token in stagedChanges.slackTokensToConnect {
            do {
                _ = try await monitor.connectSlackUserToken(token)
                slackConnectErrorMessage = nil
                slackConnectionStatusMessage = "Slack token connected."
            } catch {
                failedSlackTokens.append(token)
                slackConnectErrorMessage = AlertCalendarLanguage.errorMessage(error)
            }
        }

        if !stagedChanges.slackConnectionsToRemove.isEmpty || !stagedChanges.slackTokensToConnect.isEmpty {
            slackConnections = monitor.slackConnections()
            draft.slackStatusSyncRules = monitor.currentSettings.slackStatusSyncRules
            didAttemptSlackConnectionMetadataRefresh = false
            refreshSlackConnectionMetadataIfNeeded(force: true)
            monitor.refreshNow(reason: .slackConnectionChanged)
        }

        for token in failedSlackTokens {
            pendingChanges.stageSlackTokenConnection(token)
        }
    }

    func detectLocation() {
        Task { @MainActor in
            guard let coordinate = await monitor.detectAstronomyCoordinate() else { return }
            draft.astronomyLatitude = AppSettingsRules.roundedCoordinate(coordinate.latitude)
            draft.astronomyLongitude = AppSettingsRules.roundedCoordinate(coordinate.longitude)
        }
    }

    func connectSlackToken() {
        let token = slackUserTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            slackConnectErrorMessage = "Paste a Slack user token first."
            return
        }

        pendingChanges.stageSlackTokenConnection(token)
        slackUserTokenDraft = ""
        slackConnectErrorMessage = nil
        slackConnectionStatusMessage = "Slack connection pending. Click Apply to connect."
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
        AlertCalendarWorkspace.open(url)
    }

    func removeSlackAccount(_ connection: SlackConnection) {
        pendingChanges.stageSlackConnectionRemoval(connection)
        slackConnections.removeAll { $0.id == connection.id }
        draft.slackStatusSyncRules.removeAll { $0.connectionID == connection.id }
        draft.appleMusicStatus.connectionIDs.remove(connection.id)
        syncSlackDraftSelectionIfNeeded()
        slackConnectionStatusMessage = "Workspace removal pending. Click Apply to disconnect."
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
            slackConnections = monitor.slackConnections().filter {
                pendingChanges.slackConnectionsToRemove[$0.id] == nil
            }
            draft.slackStatusSyncRules = monitor.currentSettings.slackStatusSyncRules
            draft.appleMusicStatus.connectionIDs.formIntersection(Set(slackConnections.map(\.id)))
            syncSlackDraftSelectionIfNeeded()
            slackConnectionStatusMessage = monitor.slackConnectionStatusMessage
            isRefreshingSlackConnectionMetadata = false
        }
    }

}
