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

    func testTokenValidationRejectsHeaderInjectionWithoutKeychainAccess() {
        XCTAssertTrue(PandaScoreTokenKeychainStore.isValid("personal_test_123"))
        XCTAssertFalse(PandaScoreTokenKeychainStore.isValid(""))
        XCTAssertFalse(PandaScoreTokenKeychainStore.isValid("token\r\nAuthorization: injected"))
        XCTAssertFalse(PandaScoreTokenKeychainStore.isValid(String(repeating: "x", count: 4_097)))
    }

    func testCatalogSeparatesVerifiedProviderCoverage() {
        XCTAssertEqual(EsportsCatalog.games.count, 7)
        XCTAssertEqual(Set(EsportsCatalog.providerGames), [.leagueOfLegends, .counterStrike2, .rocketLeague, .starCraft2])
        XCTAssertNil(EsportsGame.geoGuessr.providerSlug)
        XCTAssertNil(EsportsGame.ageOfEmpires2.providerSlug)
        XCTAssertNil(EsportsGame.granTurismo7.providerSlug)
    }

    func testCompetitionNameDescribesTheIdentityUsedForFollowing() throws {
        let league = #"{"id":1,"name":"Playoffs final","status":"not_started","league":{"id":10,"name":"World Championship"},"serie":{"full_name":"2026"},"tournament":{"id":20,"name":"Playoffs"}}"#
        let fallback = #"{"id":2,"name":"Final","status":"not_started","tournament":{"id":20,"name":"Open Cup"}}"#
        let first = try PandaScoreMatchDTO.decoder().decode(PandaScoreMatchDTO.self, from: Data(league.utf8)).match(game: .leagueOfLegends, fetchedAt: Date())
        let second = try PandaScoreMatchDTO.decoder().decode(PandaScoreMatchDTO.self, from: Data(fallback.utf8)).match(game: .leagueOfLegends, fetchedAt: Date())
        XCTAssertEqual(first.competitionID, 10)
        XCTAssertEqual(first.competitionName, "World Championship")
        XCTAssertEqual(second.competitionID, 20)
        XCTAssertEqual(second.competitionName, "Open Cup")
    }
}
