import Foundation
import AppKit

enum MusicPlaybackReader {
    nonisolated static func currentPlaybackObservation(
        source: MusicPlaybackSource
    ) async -> AppleMusicPlaybackObservation {
        switch source {
        case .appleMusic:
            await AppleMusicPlaybackReader.currentPlaybackObservation()
        case .youtubeMusic:
            await YouTubeMusicPlaybackReader.currentPlaybackObservation()
        }
    }
}

enum YouTubeMusicPlaybackReader {
    private struct BrowserDescriptor: Sendable {
        enum ScriptKind: Sendable {
            case chromium
            case safari
        }

        let bundleIdentifier: String
        let scriptKind: ScriptKind
    }

    struct BrowserPlaybackPayload: Decodable, Equatable, Sendable {
        let title: String
        let artist: String
        let trackID: String
        let position: TimeInterval
        let duration: TimeInterval?
    }

    private static let browsers = [
        BrowserDescriptor(bundleIdentifier: "com.google.Chrome", scriptKind: .chromium),
        BrowserDescriptor(bundleIdentifier: "com.microsoft.edgemac", scriptKind: .chromium),
        BrowserDescriptor(bundleIdentifier: "com.brave.Browser", scriptKind: .chromium),
        BrowserDescriptor(bundleIdentifier: "company.thebrowser.Browser", scriptKind: .chromium),
        BrowserDescriptor(bundleIdentifier: "com.apple.Safari", scriptKind: .safari),
    ]

    private static let noTabMarker = "__ALERT_CALENDAR_YT_NOT_FOUND__"
    private static let stoppedMarker = "__ALERT_CALENDAR_YT_NOT_PLAYING__"
    private static let errorMarker = "__ALERT_CALENDAR_YT_ERROR__"

    nonisolated static func currentPlaybackObservation() async -> AppleMusicPlaybackObservation {
        await Task.detached(priority: .utility) {
            var sawStoppedPlayback = false
            var sawUnavailableBrowser = false

            for browser in browsers where isApplicationRunning(browser.bundleIdentifier) {
                switch browserObservation(browser) {
                case let .playing(playback):
                    return .playing(playback)
                case .stopped:
                    sawStoppedPlayback = true
                case .unavailable:
                    sawUnavailableBrowser = true
                }
            }

            if sawStoppedPlayback { return .stopped }
            return sawUnavailableBrowser ? .unavailable : .stopped
        }.value
    }

    nonisolated static func parsePayload(_ rawValue: String) -> AppleMusicPlayback? {
        guard let data = rawValue.data(using: .utf8),
              let payload = try? JSONDecoder().decode(BrowserPlaybackPayload.self, from: data),
              let artist = SlackConnection.normalizedValue(payload.artist),
              payload.position.isFinite,
              payload.position >= 0 else {
            return nil
        }

        let duration = payload.duration.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }
        let identityParts = [payload.trackID, payload.title, artist].filter { !$0.isEmpty }
        return AppleMusicPlayback(
            artist: artist,
            trackID: identityParts.joined(separator: "|"),
            elapsedDuration: payload.position,
            remainingDuration: duration.map { max(1, $0 - payload.position) }
                ?? AppleMusicPlayback.unknownDurationLease,
            durationIsKnown: duration != nil
        )
    }

    private nonisolated static func isApplicationRunning(_ bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    private nonisolated static func browserObservation(
        _ browser: BrowserDescriptor
    ) -> AppleMusicPlaybackObservation {
        let source = appleScriptSource(for: browser)
        guard let script = NSAppleScript(source: source) else { return .unavailable }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil, let rawValue = result.stringValue else { return .unavailable }

        switch rawValue {
        case noTabMarker:
            return .stopped
        case stoppedMarker:
            return .stopped
        case errorMarker:
            return .unavailable
        default:
            return parsePayload(rawValue).map(AppleMusicPlaybackObservation.playing) ?? .unavailable
        }
    }

    private nonisolated static func appleScriptSource(for browser: BrowserDescriptor) -> String {
        let javaScript = appleScriptStringLiteral(nowPlayingJavaScript)
        let executeStatement: String
        switch browser.scriptKind {
        case .chromium:
            executeStatement = "set playbackResult to execute musicTab javascript \(javaScript)"
        case .safari:
            executeStatement = "set playbackResult to do JavaScript \(javaScript) in musicTab"
        }

        return """
        tell application id "\(browser.bundleIdentifier)"
            try
                set foundMusicTab to false
                repeat with browserWindow in windows
                    repeat with musicTab in tabs of browserWindow
                        try
                            set tabURL to URL of musicTab
                            if tabURL starts with "https://music.youtube.com/" then
                                set foundMusicTab to true
                                \(executeStatement)
                                if playbackResult does not start with "__ALERT_CALENDAR_YT_" then
                                    return playbackResult
                                end if
                            end if
                        end try
                    end repeat
                end repeat
                if foundMusicTab then return "\(stoppedMarker)"
                return "\(noTabMarker)"
            on error
                return "\(errorMarker)"
            end try
        end tell
        """
    }

    private nonisolated static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static let nowPlayingJavaScript = """
    (()=>{const marker='__ALERT_CALENDAR_YT_NOT_PLAYING__';const video=document.querySelector('video');const bar=document.querySelector('ytmusic-player-bar');if(!video||!bar||video.paused||video.ended)return marker;const text=(selector)=>bar.querySelector(selector)?.textContent?.trim()||'';const title=text('.title');const byline=text('.byline');const artist=(byline.split(' • ')[0]||'').trim();if(!artist)return marker;const url=new URL(location.href);const trackID=url.searchParams.get('v')||title;const duration=Number.isFinite(video.duration)?video.duration:null;return JSON.stringify({title,artist,trackID,position:video.currentTime||0,duration});})()
    """
}
