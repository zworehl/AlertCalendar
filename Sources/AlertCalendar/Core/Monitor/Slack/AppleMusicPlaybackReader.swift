import Foundation
import AppKit

struct AppleMusicPlayback: Equatable, Sendable {
    static let expirationSafetyMargin: TimeInterval = 60
    static let unknownDurationLease: TimeInterval = 5 * 60
    static let unknownDurationRenewalLeadTime: TimeInterval = 30

    let artist: String
    let trackID: String
    let elapsedDuration: TimeInterval
    let remainingDuration: TimeInterval
    let durationIsKnown: Bool

    var statusText: String { "Listening to \(artist)" }
    var cacheIdentity: String {
        if !trackID.isEmpty { return trackID }
        if !durationIsKnown { return "\(artist)|unknown-duration" }
        return "\(artist)|\(Int((elapsedDuration + remainingDuration).rounded()))"
    }
    var statusEmoji: String {
        Int(max(0, elapsedDuration) / 30).isMultiple(of: 2) ? "🎵" : "🎶"
    }

    func expirationTimestamp(now: Date) -> Int {
        Int(
            now.addingTimeInterval(max(1, remainingDuration) + Self.expirationSafetyMargin)
                .timeIntervalSince1970
                .rounded(.up)
        )
    }

    func projected(after interval: TimeInterval) -> AppleMusicPlayback {
        guard interval.isFinite, interval > 0 else { return self }
        return AppleMusicPlayback(
            artist: artist,
            trackID: trackID,
            elapsedDuration: elapsedDuration + interval,
            remainingDuration: max(0, remainingDuration - interval),
            durationIsKnown: durationIsKnown
        )
    }

    func shouldRenewExpiration(_ expiration: Int, now: Date) -> Bool {
        guard !durationIsKnown else { return false }
        return TimeInterval(expiration) - now.timeIntervalSince1970 <= Self.unknownDurationRenewalLeadTime
    }

    static func statusDuration(
        trackDuration: TimeInterval,
        position: TimeInterval,
        followingSameArtistDuration: TimeInterval
    ) -> TimeInterval {
        let currentTrackRemaining = max(0, trackDuration - position)
        let sameArtistTail = max(0, followingSameArtistDuration)
        let total = currentTrackRemaining + sameArtistTail
        return total > 0 ? total : 120
    }

    init(
        artist: String,
        trackID: String = "",
        elapsedDuration: TimeInterval = 0,
        remainingDuration: TimeInterval = 120,
        durationIsKnown: Bool = true
    ) {
        self.artist = artist
        self.trackID = trackID
        self.elapsedDuration = elapsedDuration
        self.remainingDuration = remainingDuration
        self.durationIsKnown = durationIsKnown
    }
}

enum AppleMusicPlaybackObservation: Equatable, Sendable {
    case playing(AppleMusicPlayback)
    case stopped
    case unavailable
}

enum AppleMusicPlaybackReader {
    nonisolated static func parseTimeInterval(_ rawValue: String) -> TimeInterval? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = TimeInterval(normalized), value.isFinite else { return nil }
        return value
    }

    nonisolated static func currentPlaybackObservation() async -> AppleMusicPlaybackObservation {
        await Task.detached(priority: .utility) {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
                return .stopped
            }

            let source = """
            tell application id "com.apple.Music"
                if player state is playing then
                    set currentSong to current track
                    set currentArtist to artist of currentSong
                    set followingSameArtistDuration to 0
                    try
                        if shuffle enabled is false then
                            set sourcePlaylist to current playlist
                            set currentIndex to index of currentSong
                            set trackCount to count of tracks of sourcePlaylist
                            repeat with nextIndex from (currentIndex + 1) to trackCount
                                set candidateTrack to track nextIndex of sourcePlaylist
                                if enabled of candidateTrack is true and artist of candidateTrack is currentArtist then
                                    set followingSameArtistDuration to followingSameArtistDuration + duration of candidateTrack
                                else
                                    exit repeat
                                end if
                            end repeat
                        end if
                    end try
                    set separator to ASCII character 30
                    return currentArtist & separator & (persistent ID of currentSong) & separator & (duration of currentSong as text) & separator & (player position as text) & separator & (followingSameArtistDuration as text)
                end if
                return "__ALERT_CALENDAR_NOT_PLAYING__"
            end tell
            """
            guard let script = NSAppleScript(source: source) else { return .unavailable }
            var errorInfo: NSDictionary?
            let result = script.executeAndReturnError(&errorInfo)
            guard errorInfo == nil,
                  let rawValue = result.stringValue else {
                return .unavailable
            }
            guard rawValue != "__ALERT_CALENDAR_NOT_PLAYING__" else { return .stopped }
            let components = rawValue.components(separatedBy: String(UnicodeScalar(30)))
            guard components.count == 5,
                  let artist = SlackConnection.normalizedValue(components[0]),
                  let position = parseTimeInterval(components[3]),
                  position >= 0 else { return .unavailable }

            let parsedDuration = parseTimeInterval(components[2])
            let durationIsKnown = parsedDuration.map { $0 > 0 } ?? false
            if let parsedDuration, durationIsKnown, position > parsedDuration + 5 {
                return .unavailable
            }

            let followingSameArtistDuration = max(0, parseTimeInterval(components[4]) ?? 0)
            let remainingDuration: TimeInterval
            if let duration = parsedDuration, durationIsKnown {
                remainingDuration = max(1, max(0, duration - position) + followingSameArtistDuration)
            } else {
                remainingDuration = AppleMusicPlayback.unknownDurationLease
            }

            return .playing(
                AppleMusicPlayback(
                    artist: artist,
                    trackID: components[1],
                    elapsedDuration: position,
                    remainingDuration: remainingDuration,
                    durationIsKnown: durationIsKnown
                )
            )
        }.value
    }
}
