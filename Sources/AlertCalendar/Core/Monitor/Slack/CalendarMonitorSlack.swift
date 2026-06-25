import AppKit
import Foundation

extension CalendarMonitor {
    static let slackStatusSyncHeartbeatEvaluationInterval = CalendarMonitorCadence.slackStatusHeartbeatInterval
    static let slackDynamicStatusRotationInterval = CalendarMonitorCadence.slackDynamicStatusRotationInterval
    static let slackConnectionMetadataRefreshInterval = CalendarMonitorCadence.slackConnectionMetadataRefreshInterval
    static let slackDiagnosticsLogSizeLimit = CalendarMonitorCadence.slackDiagnosticsLogSizeLimit
    static let slackRuntimeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy h:mm:ss a"
        return formatter
    }()

    struct SlackManagedStatusState: Equatable {
        var previousStatus: SlackProfileStatusSnapshot?
        var requestedStatus: SlackProfileStatusSnapshot?
        var managedStatus: SlackProfileStatusSnapshot?
    }

    struct SlackActiveRuleState: Equatable {
        let statusText: String
        let statusEmoji: String
        let expiration: Int
    }

    struct SlackStatusSyncTarget: Equatable {
        enum Mode: Equatable {
            case clear
            case meeting(snapshot: SlackProfileStatusSnapshot)
        }

        let connection: SlackConnection
        let mode: Mode
    }

    func connectSlackUserToken(_ token: String) async throws -> SlackConnection {
        let connection = try await slackClient.connectUserToken(token)
        var settings = snapshotSettings()
        settings.slackConnections = SlackConnection.normalized(
            settings.slackConnections.filter { $0.id != connection.id } + [connection]
        )
        appendDefaultSlackStatusSyncRuleIfNeeded(to: &settings, for: connection)
        persistSettings(settings)
        return connection
    }

    func removeSlackConnection(_ connection: SlackConnection) async {
        if slackManagedStateByConnectionID[connection.id] != nil {
            do {
                try await restoreSlackStatusIfNeeded(for: connection)
            } catch {
                slackStatusSyncErrorDescription = error.localizedDescription
            }
        }

        do {
            try await slackClient.removeStoredToken(for: connection.id)
        } catch {
            slackStatusSyncErrorDescription = error.localizedDescription
        }

        var settings = snapshotSettings()
        settings.slackConnections.removeAll { $0.id == connection.id }
        settings.slackStatusSyncRules.removeAll { $0.connectionID == connection.id }
        persistSettings(settings)
        if settings.slackConnections.isEmpty {
            slackConnectionStatusMessage = nil
        }
        refreshNow(reason: .slackConnectionChanged)
    }

    func validateSlackConnection(_ connection: SlackConnection) async throws -> SlackConnection {
        let validatedConnection = try await slackClient.validateConnection(connection)
        var settings = snapshotSettings()
        settings.slackConnections = SlackConnection.normalized(
            settings.slackConnections.filter { $0.id != connection.id } + [validatedConnection]
        )
        settings.slackStatusSyncRules = settings.slackStatusSyncRules.map { rule in
            guard rule.connectionID == connection.id else { return rule }
            var updatedRule = rule
            updatedRule.connectionID = validatedConnection.id
            return updatedRule
        }
        settings.slackStatusSyncRules = SlackStatusSyncRule.normalized(
            settings.slackStatusSyncRules,
            validConnectionIDs: Set(settings.slackConnections.map(\.id)),
            validCalendarIDs: Set(availableEventCalendars.map(\.id))
        )
        persistSettings(settings)
        return validatedConnection
    }

    func slackConnections() -> [SlackConnection] {
        snapshotSettings().slackConnections
    }

    func refreshSlackConnectionMetadataIfNeeded(force: Bool = false) async {
        let storedConnections = snapshotSettings().slackConnections
        let staleValidationCutoff = fixedSecondNow().addingTimeInterval(-Self.slackConnectionMetadataRefreshInterval)
        let connectionsToRefresh = force
            ? storedConnections
            : storedConnections.filter {
                $0.profileImageURLString == nil ||
                    $0.workspaceImageURLString == nil ||
                    $0.lastValidatedAt <= staleValidationCutoff
            }

        guard !connectionsToRefresh.isEmpty else { return }

        var refreshedConnectionIDs: Set<String> = []
        var errors: [String] = []

        for connection in connectionsToRefresh {
            do {
                _ = try await validateSlackConnection(connection)
                refreshedConnectionIDs.insert(connection.id)
            } catch {
                errors.append("\(connection.displayLabel): \(error.localizedDescription)")
            }
        }

        if !refreshedConnectionIDs.isEmpty {
            slackConnectionStatusMessage = refreshedConnectionIDs.count == 1
                ? "Slack account details refreshed."
                : "\(refreshedConnectionIDs.count) Slack account details refreshed."
        }

        if !errors.isEmpty {
            slackStatusSyncErrorDescription = errors.joined(separator: " ")
        }
    }

    func preferredSlackCalendarID(from settings: AppSettings) -> String? {
        if let selectedDefault = availableEventCalendars.first(where: { settings.selectedEventCalendarIDs.contains($0.id) }) {
            return selectedDefault.id
        }

        return availableEventCalendars.first?.id
    }

    func appendDefaultSlackStatusSyncRuleIfNeeded(
        to settings: inout AppSettings,
        for connection: SlackConnection
    ) {
        guard !settings.slackStatusSyncRules.contains(where: { $0.connectionID == connection.id }) else { return }
        guard let calendarID = preferredSlackCalendarID(from: settings) else { return }

        settings.slackStatusSyncRules = SlackStatusSyncRule.normalized(
            settings.slackStatusSyncRules + [
                SlackStatusSyncRule(
                    connectionID: connection.id,
                    calendarID: calendarID,
                    statusText: settings.slackMeetingStatusText,
                    statusEmoji: settings.slackMeetingStatusEmoji,
                    isEnabled: false
                ),
            ],
            validConnectionIDs: Set(settings.slackConnections.map(\.id)),
            validCalendarIDs: Set(availableEventCalendars.map(\.id))
        )
    }

    func syncStoredSlackStatusSyncRules(availableIDs: Set<String>) {
        var settings = snapshotSettings()
        let normalizedRules = SlackStatusSyncRule.normalized(
            settings.slackStatusSyncRules,
            validConnectionIDs: Set(settings.slackConnections.map(\.id)),
            validCalendarIDs: availableIDs
        )

        guard normalizedRules != settings.slackStatusSyncRules else { return }
        settings.slackStatusSyncRules = normalizedRules
        persistSettings(settings)
    }
}
