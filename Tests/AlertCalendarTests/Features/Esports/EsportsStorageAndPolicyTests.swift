import Foundation
import XCTest
@testable import AlertCalendar

final class EsportsStorageAndPolicyTests: XCTestCase {
    func testCacheRoundTripDeduplicatesByProviderAndGameWithoutReadingKeychain() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = EsportsCacheStore(fileURL: directory.appendingPathComponent("fixtures.json"))
        var match = EsportsMatch(providerID: 1, game: .leagueOfLegends, name: "Initial", fetchedAt: Date(timeIntervalSince1970: 1))
        let old = match
        match.name = "Updated"
        match.fetchedAt = Date(timeIntervalSince1970: 2)
        let otherGame = EsportsMatch(providerID: 1, game: .starCraft2, name: "Player final")
        try await cache.save(matches: [old, match, otherGame])
        let restored = await cache.load()
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored.first { $0.game == .leagueOfLegends }?.name, "Updated")
        XCTAssertEqual(Set(restored.map(\.id)).count, 2)
    }

    func testCacheRejectsMalformedOrUnsupportedVersion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fixtures.json")
        try Data(#"{"version":999,"matches":[]}"#.utf8).write(to: url)
        let cache = EsportsCacheStore(fileURL: url)
        let restored = await cache.load()
        XCTAssertTrue(restored.isEmpty)
    }

    func testStreamPolicyRejectsCredentialInjectionAndLookalikeHosts() {
        for value in ["http://twitch.tv/channel", "https://twitch.tv.evil.test/channel", "https://user:password@youtube.com/watch", "https://evil.test", "file:///tmp/private", "https://youtube.com:8443/"] {
            XCTAssertNil(EsportsStreamURLPolicy.safeURL(URL(string: value)), value)
        }
        XCTAssertNotNil(EsportsStreamURLPolicy.safeURL(URL(string: "https://www.twitch.tv/channel")))
        XCTAssertNotNil(EsportsStreamURLPolicy.safeURL(URL(string: "https://youtu.be/video")))
    }

    func testLegacyCacheRetainsCanonicalIdentityAndAttribution() throws {
        let original = EsportsMatch(providerID: 1711021, game: .leagueOfLegends, name: "Final")
        let encoded = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(EsportsMatch.self, from: encoded)
        XCTAssertEqual(restored.id, "pandascore:leagueOfLegends:1711021")
        XCTAssertEqual(restored.sourceAttributionText, "Source: PandaScore")
        XCTAssertNil(restored.feedSourceURL)
        XCTAssertNil(restored.feedCompetitionKey)
    }

    func testCatalogExposesOnlyVerifiedProviderCoverageAndDecodesLegacyGames() throws {
        let supported: Set<EsportsGame> = [.leagueOfLegends, .counterStrike2, .rocketLeague, .starCraft2]
        XCTAssertEqual(Set(EsportsCatalog.games), supported)
        XCTAssertEqual(Set(EsportsCatalog.providerGames), supported)
        for game in [EsportsGame.ageOfEmpires2, .geoGuessr, .granTurismo7] {
            let restored = try JSONDecoder().decode(EsportsGame.self, from: JSONEncoder().encode(game))
            XCTAssertEqual(restored, game)
            XCTAssertFalse(EsportsCatalog.supports(restored))
        }
        XCTAssertNil(EsportsGame.geoGuessr.providerSlug)
        XCTAssertNil(EsportsGame.ageOfEmpires2.providerSlug)
        XCTAssertNil(EsportsGame.granTurismo7.providerSlug)
    }

    func testPublicMetadataSurvivesCacheWithoutChangingUpstreamIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = EsportsCacheStore(fileURL: directory.appendingPathComponent("fixtures.json"))
        var match = EsportsMatch(providerID: 1711021, game: .leagueOfLegends, name: "Bilibili Gaming vs Gen.G", competitionName: "Worlds")
        match.feedSourceURL = PublicEsportsCalendarClient.sourceURL
        match.feedSourceAttribution = PublicEsportsCalendarClient.attribution
        match.feedCompetitionKey = "esport-calendar:leagueOfLegends:Worlds"
        try await cache.save(matches: [match])
        let restored = await cache.load()
        XCTAssertEqual(restored, [match])
        XCTAssertEqual(restored.first?.id, "pandascore:leagueOfLegends:1711021")
        XCTAssertEqual(restored.first?.competitionKey, "esport-calendar:leagueOfLegends:Worlds")
        XCTAssertEqual(restored.first?.sourceAttributionText, PublicEsportsCalendarClient.attribution)
    }
}
