import XCTest
@testable import AlertCalendar

final class YouTubeMusicPlaybackReaderTests: SlackStatusSyncTestCase {
    func testPayloadUsesBrowserTimingWithoutExtraSlackLease() throws {
        let payload = """
        {"title":"Hyperballad","artist":"Björk","trackID":"video-123","position":60.5,"duration":240.25}
        """

        let playback = try XCTUnwrap(YouTubeMusicPlaybackReader.parsePayload(payload))

        XCTAssertEqual(playback.artist, "Björk")
        XCTAssertEqual(playback.trackID, "video-123|Hyperballad|Björk")
        XCTAssertEqual(playback.elapsedDuration, 60.5)
        XCTAssertEqual(playback.remainingDuration, 179.75)
        XCTAssertTrue(playback.durationIsKnown)
    }

    func testPayloadFallsBackToRenewableLeaseWhenDurationIsUnknown() throws {
        let payload = """
        {"title":"Live Radio","artist":"Station","trackID":"stream","position":32,"duration":null}
        """

        let playback = try XCTUnwrap(YouTubeMusicPlaybackReader.parsePayload(payload))

        XCTAssertEqual(playback.remainingDuration, AppleMusicPlayback.unknownDurationLease)
        XCTAssertFalse(playback.durationIsKnown)
    }
}
