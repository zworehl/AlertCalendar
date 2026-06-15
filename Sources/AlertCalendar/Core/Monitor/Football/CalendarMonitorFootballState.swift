import Foundation

struct CalendarMonitorFootballState {
    var matchesByID: [String: FootballFixtureMatch] = [:]
    var managedEventRecords: [ManagedFootballEventRecord] = []
    var localLogoPathsByCompetitionSlug: [String: String] = [:]
    var localLogoPathsByTeamID: [String: String] = [:]
    var lastMenuRefreshDate: Date?
    var lastManagedSyncDate: Date?
    var lastManagedCleanupDate: Date?
    var lastManagedRecoveryDate: Date?
    var lastLegacyMigrationDate: Date?
    var activeGoalHighlight: FootballGoalHighlight?
    var deliveredNotificationKeys: Set<String> = []
    var cachedManagedSnapshots: [ManagedFootballEventSnapshot] = []
    var isManagedSnapshotCacheValid = false
    var didEventStoreChange = false
}

extension CalendarMonitor {
    var footballMatchesByID: [String: FootballFixtureMatch] {
        get { footballState.matchesByID }
        set { footballState.matchesByID = newValue }
    }

    var managedFootballEventRecords: [ManagedFootballEventRecord] {
        get { footballState.managedEventRecords }
        set { footballState.managedEventRecords = newValue }
    }

    var footballLocalLogoPathsByCompetitionSlug: [String: String] {
        get { footballState.localLogoPathsByCompetitionSlug }
        set { footballState.localLogoPathsByCompetitionSlug = newValue }
    }

    var footballLocalLogoPathsByTeamID: [String: String] {
        get { footballState.localLogoPathsByTeamID }
        set { footballState.localLogoPathsByTeamID = newValue }
    }

    var lastFootballMenuRefreshDate: Date? {
        get { footballState.lastMenuRefreshDate }
        set { footballState.lastMenuRefreshDate = newValue }
    }

    var lastFootballManagedSyncDate: Date? {
        get { footballState.lastManagedSyncDate }
        set { footballState.lastManagedSyncDate = newValue }
    }

    var lastFootballManagedCleanupDate: Date? {
        get { footballState.lastManagedCleanupDate }
        set { footballState.lastManagedCleanupDate = newValue }
    }

    var lastFootballManagedRecoveryDate: Date? {
        get { footballState.lastManagedRecoveryDate }
        set { footballState.lastManagedRecoveryDate = newValue }
    }

    var lastFootballLegacyMigrationDate: Date? {
        get { footballState.lastLegacyMigrationDate }
        set { footballState.lastLegacyMigrationDate = newValue }
    }

    var activeFootballGoalHighlight: FootballGoalHighlight? {
        get { footballState.activeGoalHighlight }
        set { footballState.activeGoalHighlight = newValue }
    }

    var deliveredFootballNotificationKeys: Set<String> {
        get { footballState.deliveredNotificationKeys }
        set { footballState.deliveredNotificationKeys = newValue }
    }

    var cachedManagedFootballSnapshots: [ManagedFootballEventSnapshot] {
        get { footballState.cachedManagedSnapshots }
        set { footballState.cachedManagedSnapshots = newValue }
    }

    var isManagedFootballSnapshotCacheValid: Bool {
        get { footballState.isManagedSnapshotCacheValid }
        set { footballState.isManagedSnapshotCacheValid = newValue }
    }

    var didFootballEventStoreChange: Bool {
        get { footballState.didEventStoreChange }
        set { footballState.didEventStoreChange = newValue }
    }
}
