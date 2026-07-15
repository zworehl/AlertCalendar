import Foundation

enum GameStore: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case steam
    case xbox
    case playStation
    case nintendoSwitch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steam:
            return "Steam"
        case .xbox:
            return "Xbox"
        case .playStation:
            return "PlayStation Store"
        case .nintendoSwitch:
            return "Nintendo eShop"
        }
    }

    var systemImageName: String {
        switch self {
        case .steam, .nintendoSwitch:
            return "gamecontroller.fill"
        case .xbox:
            return "xbox.logo"
        case .playStation:
            return "playstation.logo"
        }
    }

    static func infer(from url: URL?) -> GameStore? {
        guard var host = url?.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        while host.last == "." {
            host.removeLast()
        }

        if hostMatches(host, domain: "steampowered.com")
            || hostMatches(host, domain: "steamgames.com")
            || hostMatches(host, domain: "steamcommunity.com") {
            return .steam
        }
        if hostMatches(host, domain: "xbox.com")
            || hostMatches(host, domain: "microsoft.com")
            || hostMatches(host, domain: "microsoftstore.com") {
            return .xbox
        }
        if hostMatches(host, domain: "playstation.com")
            || hostMatches(host, domain: "playstation.net") {
            return .playStation
        }

        let nintendoDomains = [
            "nintendo.com",
            "nintendo.co.jp",
            "nintendo.co.uk",
            "nintendo-europe.com",
        ]
        if nintendoDomains.contains(where: { hostMatches(host, domain: $0) }) {
            return .nintendoSwitch
        }
        return nil
    }

    private static func hostMatches(_ host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix(".\(domain)")
    }
}
