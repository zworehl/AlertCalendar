import XCTest
@testable import AlertCalendar

final class MusicEmojiRotationTests: XCTestCase {
    func testSlackCatalogAcceptsStandardEmojiAndAliasesOnly() {
        XCTAssertEqual(SlackEmojiCatalog.normalizedEmoji("🎵"), "🎵")
        XCTAssertEqual(SlackEmojiCatalog.normalizedEmoji(" :notes: "), "🎶")
        XCTAssertEqual(SlackEmojiCatalog.normalizedEmoji(":dog:"), "🐶")
        XCTAssertEqual(SlackEmojiCatalog.normalizedEmoji("👍🏽"), "👍🏽")
        XCTAssertNil(SlackEmojiCatalog.normalizedEmoji("music"))
        XCTAssertNil(SlackEmojiCatalog.normalizedEmoji("🎵🎶"))
        XCTAssertNil(SlackEmojiCatalog.normalizedEmoji(":not_a_slack_emoji:"))
    }

    func testRotationUsesAnyConfiguredSequenceAndKeepsExistingDefaults() {
        let playback = AppleMusicPlayback(artist: "Artist", elapsedDuration: 90)
        XCTAssertEqual(AppleMusicStatusSettings().emojis, ["🎵", "🎶"])
        XCTAssertEqual(playback.statusEmoji, "🎶")

        let emojis = ["🎵", "🎶", "🎤", "🎸"]
        XCTAssertEqual(playback.statusEmoji(from: emojis), "🎸")
        XCTAssertEqual(AppleMusicPlayback(artist: "Artist", elapsedDuration: 120).statusEmoji(from: emojis), "🎵")
        XCTAssertEqual(playback.statusEmoji(from: ["🎷"]), "🎷")
    }

    func testSettingsMigrateAndDiscardUnsupportedEntries() throws {
        let legacy = try XCTUnwrap(#"{"isEnabled":true,"connectionIDs":[],"priority":6}"#.data(using: .utf8))
        XCTAssertEqual(try JSONDecoder().decode(AppleMusicStatusSettings.self, from: legacy).emojis, ["🎵", "🎶"])

        let settings = AppleMusicStatusSettings(emojis: [":notes:", "invalid", "🎸"])
        XCTAssertEqual(settings.emojis, ["🎶", "🎸"])
        XCTAssertEqual(try JSONDecoder().decode(AppleMusicStatusSettings.self, from: JSONEncoder().encode(settings)).emojis, ["🎶", "🎸"])
        XCTAssertEqual(AppleMusicStatusSettings(emojis: ["invalid"]).emojis, ["🎵", "🎶"])
    }

    func testSettingsLimitEmojiSequenceToTen() throws {
        let entries = Array(repeating: "🎵", count: 11)
        XCTAssertEqual(AppleMusicStatusSettings(emojis: entries).emojis.count, 10)

        let data = try JSONEncoder().encode(entries)
        let encodedEntries = try XCTUnwrap(String(data: data, encoding: .utf8))
        let settingsData = try XCTUnwrap("{\"emojis\":\(encodedEntries)}".data(using: .utf8))
        let decoded = try JSONDecoder().decode(AppleMusicStatusSettings.self, from: settingsData)
        XCTAssertEqual(decoded.emojis.count, 10)
    }
}
