import Foundation

enum SettingsPendingMutation: Equatable {
    case add
    case remove

    var makesItemPresent: Bool {
        self == .add
    }
}

struct SettingsPendingItemChange<Item: Equatable>: Equatable {
    let item: Item
    let mutation: SettingsPendingMutation
}

struct SettingsPendingChanges: Equatable {
    var footballFixtures: [String: SettingsPendingItemChange<FootballFixtureMatch>] = [:]
    var gameSales: [String: SettingsPendingItemChange<GameSaleEvent>] = [:]
    var slackConnectionsToRemove: [String: SlackConnection] = [:]
    var slackTokensToConnect: [String] = []

    var isEmpty: Bool {
        footballFixtures.isEmpty
            && gameSales.isEmpty
            && slackConnectionsToRemove.isEmpty
            && slackTokensToConnect.isEmpty
    }

    static func footballFixtureKey(for match: FootballFixtureMatch) -> String {
        "\(match.competitionSlug)|\(match.id)"
    }

    func footballFixtureIsPresent(
        _ match: FootballFixtureMatch,
        persistedIsPresent: Bool
    ) -> Bool {
        footballFixtures[Self.footballFixtureKey(for: match)]?.mutation.makesItemPresent
            ?? persistedIsPresent
    }

    mutating func toggleFootballFixture(
        _ match: FootballFixtureMatch,
        persistedIsPresent: Bool
    ) {
        let key = Self.footballFixtureKey(for: match)
        let desiredPresence = !footballFixtureIsPresent(match, persistedIsPresent: persistedIsPresent)
        Self.setPendingItem(
            match,
            desiredPresence: desiredPresence,
            persistedIsPresent: persistedIsPresent,
            key: key,
            changes: &footballFixtures
        )
    }

    func gameSaleIsPresent(
        _ sale: GameSaleEvent,
        persistedIsPresent: Bool
    ) -> Bool {
        gameSales[sale.id]?.mutation.makesItemPresent ?? persistedIsPresent
    }

    mutating func toggleGameSale(
        _ sale: GameSaleEvent,
        persistedIsPresent: Bool
    ) {
        let desiredPresence = !gameSaleIsPresent(sale, persistedIsPresent: persistedIsPresent)
        Self.setPendingItem(
            sale,
            desiredPresence: desiredPresence,
            persistedIsPresent: persistedIsPresent,
            key: sale.id,
            changes: &gameSales
        )
    }

    mutating func stageSlackConnectionRemoval(_ connection: SlackConnection) {
        slackConnectionsToRemove[connection.id] = connection
    }

    mutating func stageSlackTokenConnection(_ token: String) {
        guard !slackTokensToConnect.contains(token) else { return }
        slackTokensToConnect.append(token)
    }

    private static func setPendingItem<Item: Equatable>(
        _ item: Item,
        desiredPresence: Bool,
        persistedIsPresent: Bool,
        key: String,
        changes: inout [String: SettingsPendingItemChange<Item>]
    ) {
        guard desiredPresence != persistedIsPresent else {
            changes.removeValue(forKey: key)
            return
        }

        changes[key] = SettingsPendingItemChange(
            item: item,
            mutation: desiredPresence ? .add : .remove
        )
    }
}
