import XCTest
@testable import AlertCalendar

final class GameSaleEventTests: XCTestCase {
    func testStoreInferenceUsesKnownHostsWithoutTrustingDeceptiveSuffixes() {
        XCTAssertEqual(
            GameStore.infer(from: URL(string: "https://partner.steamgames.com/doc/marketing/upcoming_events")),
            .steam
        )
        XCTAssertEqual(
            GameStore.infer(from: URL(string: "https://store.steampowered.com/sale/autumn")),
            .steam
        )
        XCTAssertEqual(
            GameStore.infer(from: URL(string: "https://www.xbox.com/en-US/promotions/sales/sales-and-specials")),
            .xbox
        )
        XCTAssertEqual(
            GameStore.infer(from: URL(string: "https://apps.microsoft.com/detail/example")),
            .xbox
        )
        XCTAssertEqual(
            GameStore.infer(from: URL(string: "https://www.microsoftstore.com/store/example")),
            .xbox
        )
        XCTAssertEqual(
            GameStore.infer(from: URL(string: "https://store.playstation.com/en-us/pages/deals")),
            .playStation
        )
        XCTAssertEqual(
            GameStore.infer(from: URL(string: "https://www.nintendo.com/us/store/sales-and-deals/")),
            .nintendoSwitch
        )
        XCTAssertNil(
            GameStore.infer(from: URL(string: "https://steampowered.com.example.test/fake-sale"))
        )
        XCTAssertNil(GameStore.infer(from: URL(string: "https://example.test/steam-sale")))
        XCTAssertNil(GameStore.infer(from: nil))
    }

    func testEventIdentityIsStableAndNamespacedByStore() throws {
        let startDate = Date(timeIntervalSince1970: 1_788_115_200)
        let endDate = Date(timeIntervalSince1970: 1_788_806_400)
        let steamEvent = GameSaleEvent(
            store: .steam,
            sourceID: "seasonal-autumn-2026",
            title: "Steam Autumn Sale",
            startDate: startDate,
            endDateExclusive: endDate,
            officialURL: try XCTUnwrap(URL(string: "https://partner.steamgames.com/doc/marketing/upcoming_events#5"))
        )
        let xboxEvent = GameSaleEvent(
            store: .xbox,
            sourceID: steamEvent.sourceID,
            title: steamEvent.title,
            startDate: steamEvent.startDate,
            endDateExclusive: steamEvent.endDateExclusive,
            officialURL: try XCTUnwrap(URL(string: "https://www.xbox.com/"))
        )

        XCTAssertEqual(steamEvent.id, "steam:seasonal-autumn-2026")
        XCTAssertEqual(xboxEvent.id, "xbox:seasonal-autumn-2026")
        XCTAssertNotEqual(steamEvent.id, xboxEvent.id)
        XCTAssertTrue(steamEvent.isAllDay)

        let encoded = try JSONEncoder().encode(steamEvent)
        XCTAssertEqual(try JSONDecoder().decode(GameSaleEvent.self, from: encoded), steamEvent)
    }

    func testStoreMetadataIsStable() {
        XCTAssertEqual(GameStore.allCases.map(\.rawValue), [
            "steam",
            "xbox",
            "playStation",
            "nintendoSwitch",
        ])
        XCTAssertEqual(GameStore.steam.title, "Steam")
        XCTAssertEqual(GameStore.xbox.title, "Xbox")
        XCTAssertEqual(GameStore.playStation.title, "PlayStation Store")
        XCTAssertEqual(GameStore.nintendoSwitch.title, "Nintendo eShop")
    }
}
