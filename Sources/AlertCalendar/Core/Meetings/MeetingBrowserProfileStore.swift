import Foundation

enum MeetingBrowserProfileStore {
    static func profilesByBrowser(for browsers: [MeetingBrowserKind]) -> [MeetingBrowserKind: [MeetingBrowserProfileOption]] {
        Dictionary(
            uniqueKeysWithValues: browsers.map { browser in
                (browser, profiles(for: browser))
            }
        )
    }

    static func profiles(for browser: MeetingBrowserKind) -> [MeetingBrowserProfileOption] {
        switch browser.profileFamily {
        case .chromium:
            guard let relativePath = browser.chromiumLocalStateRelativePath else {
                return [defaultChromiumProfile()]
            }

            let localStateURL = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent(relativePath)
            guard let data = try? Data(contentsOf: localStateURL) else {
                return [defaultChromiumProfile()]
            }

            let parsedProfiles = chromiumProfiles(fromLocalStateData: data)
            return parsedProfiles.isEmpty ? [defaultChromiumProfile()] : parsedProfiles
        case .firefox:
            guard let relativePath = browser.firefoxProfilesIniRelativePath else {
                return [defaultFirefoxProfile()]
            }

            let profilesURL = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent(relativePath)
            guard let data = try? Data(contentsOf: profilesURL) else {
                return [defaultFirefoxProfile()]
            }

            let parsedProfiles = firefoxProfiles(fromProfilesIniData: data)
            return parsedProfiles.isEmpty ? [defaultFirefoxProfile()] : parsedProfiles
        case .none:
            return [MeetingBrowserProfileOption.automatic(for: browser)]
        }
    }

    static func chromiumProfiles(fromLocalStateData data: Data) -> [MeetingBrowserProfileOption] {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let profile = object["profile"] as? [String: Any],
            let infoCache = profile["info_cache"] as? [String: Any]
        else {
            return []
        }

        return infoCache.compactMap { directory, value -> MeetingBrowserProfileOption? in
            guard let metadata = value as? [String: Any] else { return nil }

            let rawName = metadata["name"] as? String
            let gaiaName = metadata["gaia_name"] as? String
            let shortcutName = metadata["shortcut_name"] as? String
            let emailAddress = metadata["user_name"] as? String
            let displayName = [
                gaiaName,
                shortcutName,
                rawName,
                directory,
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? directory

            let detailText: String
            if let emailAddress = emailAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
               !emailAddress.isEmpty {
                detailText = "\(directory) - \(emailAddress)"
            } else {
                detailText = directory
            }

            return MeetingBrowserProfileOption(
                id: directory,
                displayName: displayName,
                detailText: detailText,
                isDefault: directory == MeetingBrowserRoute.defaultChromeProfileID
            )
        }
        .sorted { lhs, rhs in
            if lhs.id == MeetingBrowserRoute.defaultChromeProfileID {
                return true
            }
            if rhs.id == MeetingBrowserRoute.defaultChromeProfileID {
                return false
            }

            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    static func firefoxProfiles(fromProfilesIniData data: Data) -> [MeetingBrowserProfileOption] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var sections: [[String: String]] = []
        var currentName: String?
        var currentValues: [String: String] = [:]

        func flushSection() {
            guard let currentName, currentName.hasPrefix("Profile") else { return }
            sections.append(currentValues)
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                flushSection()
                currentName = String(line.dropFirst().dropLast())
                currentValues = [:]
                continue
            }

            guard let separatorIndex = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            currentValues[key] = value
        }

        flushSection()

        return sections.compactMap { values -> MeetingBrowserProfileOption? in
            guard let name = values["Name"], !name.isEmpty else { return nil }
            let path = values["Path"]
            return MeetingBrowserProfileOption(
                id: name,
                displayName: name,
                detailText: (path?.isEmpty == false) ? path ?? name : name,
                isDefault: values["Default"] == "1"
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault
            }

            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func defaultChromiumProfile() -> MeetingBrowserProfileOption {
        MeetingBrowserProfileOption(
            id: MeetingBrowserRoute.defaultChromeProfileID,
            displayName: "Default",
            detailText: MeetingBrowserRoute.defaultChromeProfileID,
            isDefault: true
        )
    }

    private static func defaultFirefoxProfile() -> MeetingBrowserProfileOption {
        MeetingBrowserProfileOption(
            id: MeetingBrowserRoute.defaultFirefoxProfileID,
            displayName: MeetingBrowserRoute.defaultFirefoxProfileID,
            detailText: MeetingBrowserRoute.defaultFirefoxProfileID,
            isDefault: true
        )
    }
}
