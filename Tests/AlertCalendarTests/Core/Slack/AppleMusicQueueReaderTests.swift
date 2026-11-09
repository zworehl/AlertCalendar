import XCTest
@testable import AlertCalendar

final class AppleMusicQueueReaderTests: XCTestCase {
    func testStreamingAlbumExpirationIncludesBothDiscsAndOneSafetyMinute() throws {
        let tracks = [track("Previous", seconds: 120), track("Current", seconds: 574)] +
            (1...19).map { track("Following \($0)", seconds: 300) }
        let following = try XCTUnwrap(tail(in: queue(tracks)))
        XCTAssertEqual(following, 19 * 300)
        let playback = AppleMusicPlayback(
            artist: "Metallica",
            remainingDuration: AppleMusicPlayback.statusDuration(
                trackDuration: 574,
                position: 147,
                followingSameArtistDuration: following
            )
        )
        XCTAssertEqual(playback.expirationTimestamp(now: Date(timeIntervalSince1970: 1_000)), 7_187)
    }

    func testStopsAtFirstDifferentArtistRatherThanCountingLaterReturn() throws {
        let tracks = [
            track("Current"), track("Next", seconds: 210.5),
            track("Other", artist: "Björk"), track("Later", seconds: 500),
        ]
        XCTAssertEqual(try tail(in: queue(tracks)), 210.5)
    }

    func testCountsConsecutiveArtistAcrossQueueSegmentsAndAlbums() throws {
        let first = segment([track("Current"), track("Next", seconds: 210)])
        let second = segment([track("Other album", album: "S&M2", seconds: 310)])
        XCTAssertEqual(try tail(in: ["shuffleMode": "off", "sega": [first, second]]), 520)
    }

    func testLastQueuedTrackHasNoTail() throws {
        XCTAssertEqual(try tail(in: queue([track("Previous"), track("Current")])), 0)
    }

    func testRejectsShuffleStaleAndAmbiguousQueues() throws {
        var shuffled = queue([track("Current"), track("Next")])
        shuffled["shuffleMode"] = "songs"
        XCTAssertNil(try tail(in: shuffled))
        XCTAssertNil(try tail(in: queue([track("Other song")])))
        XCTAssertNil(try tail(in: queue([track("Current", album: "Other album")])))
        XCTAssertNil(try tail(in: queue([track("Current"), track("Current")])))
        XCTAssertNil(AppleMusicQueueReader.followingSameArtistDuration(
            data: Data("invalid".utf8), title: "Current", artist: "Metallica", album: "S&M"
        ))
    }

    func testDoesNotSkipUnknownQueuedTracksOrInventTheirDuration() throws {
        XCTAssertEqual(try tail(in: queue([track("Current"), [:], track("Later")])), 0)
        XCTAssertEqual(try tail(in: queue([track("Current"), track("Unknown", seconds: 0), track("Later")])), 0)
    }

    func testQueueEditsRefreshExpirationDuringSameTrack() {
        let now = Date(timeIntervalSince1970: 1_000)
        let original = AppleMusicPlayback(artist: "Metallica", trackID: "same", remainingDuration: 400)
        let expiration = original.expirationTimestamp(now: now)
        let later = now.addingTimeInterval(5)
        XCTAssertFalse(original.projected(after: 5).shouldRenewExpiration(expiration, now: later))
        XCTAssertTrue(AppleMusicPlayback(artist: "Metallica", trackID: "same", remainingDuration: 1_000)
            .shouldRenewExpiration(expiration, now: later))
        XCTAssertTrue(AppleMusicPlayback(artist: "Metallica", trackID: "same", remainingDuration: 100)
            .shouldRenewExpiration(expiration, now: later))
        // Subsecond observation jitter should keep the stable expiration.
        XCTAssertFalse(original.projected(after: 4.2).shouldRenewExpiration(expiration, now: later))
    }

    private func tail(in plist: [String: Any]) throws -> TimeInterval? {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        return AppleMusicQueueReader.followingSameArtistDuration(
            data: data, title: "Current", artist: "Metallica", album: "S&M"
        )
    }

    private func queue(_ tracks: [[String: Any]]) -> [String: Any] {
        ["shuffleMode": "off", "sega": [segment(tracks)]]
    }

    private func segment(_ tracks: [[String: Any]]) -> [String: Any] {
        ["items": ["shuffleMode": "off", "list": ["items": ["iar": tracks]]]]
    }

    private func track(
        _ title: String,
        artist: String = "Metallica",
        album: String = "S&M",
        seconds: TimeInterval = 240
    ) -> [String: Any] {
        ["pm": ["stplat": [
            "name": title, "artistName": artist, "collectionName": album,
            "durationInMillis": seconds * 1_000,
        ]]]
    }
}
