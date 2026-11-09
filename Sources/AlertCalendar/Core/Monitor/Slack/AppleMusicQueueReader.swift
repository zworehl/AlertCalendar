import Foundation

enum AppleMusicQueueReader {
    nonisolated static func followingSameArtistDuration(
        title: String,
        artist: String,
        album: String
    ) -> TimeInterval? {
        let manager = FileManager.default
        guard let library = manager.urls(for: .libraryDirectory, in: .userDomainMask).first,
              let music = manager.urls(for: .musicDirectory, in: .userDomainMask).first else { return nil }
        let preferencesURL = library.appendingPathComponent("Preferences/com.apple.Music.plist")
        let preferences = (try? Data(contentsOf: preferencesURL)).flatMap(propertyList)
        let libraryURL = (preferences?["library-url"] as? String).flatMap(URL.init(string:))
            ?? music.appendingPathComponent("Music/Music Library.musiclibrary", isDirectory: true)
        guard libraryURL.isFileURL,
              let data = try? Data(contentsOf: libraryURL.appendingPathComponent("Preferences/Queue.dat")) else {
            return nil
        }
        return followingSameArtistDuration(data: data, title: title, artist: artist, album: album)
    }

    nonisolated static func followingSameArtistDuration(
        data: Data,
        title: String,
        artist: String,
        album: String
    ) -> TimeInterval? {
        guard let queue = propertyList(data),
              queue["shuffleMode"] as? String == "off",
              let segments = queue["sega"] as? [[String: Any]] else { return nil }

        var tracks: [[String: Any]] = []
        for segment in segments {
            guard let items = segment["items"] as? [String: Any],
                  items["shuffleMode"] as? String == "off",
                  let list = items["list"] as? [String: Any],
                  let entries = list["items"] as? [String: Any],
                  let segmentTracks = entries["iar"] as? [[String: Any]] else { return nil }
            tracks.append(contentsOf: segmentTracks)
        }

        // A stale queue or duplicate occurrence cannot identify the current position.
        let matches = tracks.indices.filter { index in
            guard let metadata = metadata(for: tracks[index]) else { return false }
            return metadata["name"] as? String == title &&
                metadata["artistName"] as? String == artist &&
                metadata["collectionName"] as? String == album
        }
        guard matches.count == 1, let currentIndex = matches.first else { return nil }

        var duration: TimeInterval = 0
        for track in tracks.dropFirst(currentIndex + 1) {
            guard let metadata = metadata(for: track),
                  metadata["artistName"] as? String == artist,
                  let milliseconds = metadata["durationInMillis"] as? NSNumber else { break }
            let seconds = milliseconds.doubleValue / 1_000
            guard seconds.isFinite, seconds > 0 else { break }
            duration += seconds
        }
        return duration
    }

    nonisolated private static func metadata(for track: [String: Any]) -> [String: Any]? {
        (track["pm"] as? [String: Any])?["stplat"] as? [String: Any]
    }

    nonisolated private static func propertyList(_ data: Data) -> [String: Any]? {
        (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}
