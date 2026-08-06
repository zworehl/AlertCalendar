import Foundation

struct MeetingBrowserProfileCatalog: Equatable {
    var profilesByBrowser: [MeetingBrowserKind: [MeetingBrowserProfileOption]]
    var issuesByBrowser: [MeetingBrowserKind: MeetingBrowserProfileLoadIssue]
}

struct MeetingBrowserProfileLoadIssue: Identifiable, Equatable {
    enum Reason: Equatable {
        case accessDenied
        case sourceMissing
        case invalidData
        case unreadable
    }

    let browser: MeetingBrowserKind
    let reason: Reason
    let sourcePath: String
    let technicalDescription: String

    var id: MeetingBrowserKind { browser }

    var message: String {
        switch reason {
        case .accessDenied:
            return "macOS blocked access to \(browser.title) profile data."
        case .sourceMissing:
            return "\(browser.title) profile data was not found. Open \(browser.title) once, then retry."
        case .invalidData:
            return "\(browser.title) profile data could not be decoded."
        case .unreadable:
            return "\(browser.title) profile data could not be read."
        }
    }
}

enum MeetingBrowserProfileAuthorizationStore {
    private static let bookmarksKey = "meetingBrowserProfileSourceBookmarks"

    static func authorizedSourceURLs(
        for browsers: [MeetingBrowserKind],
        defaults: UserDefaults = .standard
    ) -> [MeetingBrowserKind: URL] {
        let bookmarks = storedBookmarks(defaults: defaults)
        var resolvedURLs: [MeetingBrowserKind: URL] = [:]

        for browser in browsers {
            guard let bookmark = bookmarks[browser.rawValue] else { continue }

            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                continue
            }

            resolvedURLs[browser] = url

            if isStale {
                try? authorize(url, for: browser, defaults: defaults)
            }
        }

        return resolvedURLs
    }

    static func authorize(
        _ sourceURL: URL,
        for browser: MeetingBrowserKind,
        defaults: UserDefaults = .standard
    ) throws {
        let bookmark = try sourceURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        var bookmarks = storedBookmarks(defaults: defaults)
        bookmarks[browser.rawValue] = bookmark
        defaults.set(bookmarks, forKey: bookmarksKey)
    }

    private static func storedBookmarks(defaults: UserDefaults) -> [String: Data] {
        guard let values = defaults.dictionary(forKey: bookmarksKey) else { return [:] }
        return values.reduce(into: [:]) { result, entry in
            if let bookmark = entry.value as? Data {
                result[entry.key] = bookmark
            }
        }
    }
}

enum MeetingBrowserProfileStore {
    private struct LoadResult {
        let profiles: [MeetingBrowserProfileOption]
        let issue: MeetingBrowserProfileLoadIssue?
    }

    static func catalog(for browsers: [MeetingBrowserKind]) -> MeetingBrowserProfileCatalog {
        catalog(
            for: browsers,
            homeDirectoryURL: FileManager.default.homeDirectoryForCurrentUser,
            authorizedSourceURLs: MeetingBrowserProfileAuthorizationStore.authorizedSourceURLs(
                for: browsers
            )
        )
    }

    static func catalog(
        for browsers: [MeetingBrowserKind],
        homeDirectoryURL: URL,
        authorizedSourceURLs: [MeetingBrowserKind: URL] = [:]
    ) -> MeetingBrowserProfileCatalog {
        var profilesByBrowser: [MeetingBrowserKind: [MeetingBrowserProfileOption]] = [:]
        var issuesByBrowser: [MeetingBrowserKind: MeetingBrowserProfileLoadIssue] = [:]

        for browser in browsers {
            let result = loadProfiles(
                for: browser,
                homeDirectoryURL: homeDirectoryURL,
                authorizedSourceURL: authorizedSourceURLs[browser]
            )
            profilesByBrowser[browser] = result.profiles
            if let issue = result.issue {
                issuesByBrowser[browser] = issue
            }
        }

        return MeetingBrowserProfileCatalog(
            profilesByBrowser: profilesByBrowser,
            issuesByBrowser: issuesByBrowser
        )
    }

    static func profilesByBrowser(for browsers: [MeetingBrowserKind]) -> [MeetingBrowserKind: [MeetingBrowserProfileOption]] {
        catalog(for: browsers).profilesByBrowser
    }

    static func profiles(for browser: MeetingBrowserKind) -> [MeetingBrowserProfileOption] {
        catalog(for: [browser]).profilesByBrowser[browser] ?? [
            MeetingBrowserProfileOption.automatic(for: browser),
        ]
    }

    static func expectedSourceURL(
        for browser: MeetingBrowserKind,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        let relativePath: String?
        switch browser.profileFamily {
        case .chromium:
            relativePath = browser.chromiumLocalStateRelativePath
        case .firefox:
            relativePath = browser.firefoxProfilesIniRelativePath
        case .none:
            relativePath = nil
        }

        return relativePath.map {
            homeDirectoryURL.appendingPathComponent($0)
        }
    }

    private static func loadProfiles(
        for browser: MeetingBrowserKind,
        homeDirectoryURL: URL,
        authorizedSourceURL: URL?
    ) -> LoadResult {
        switch browser.profileFamily {
        case .chromium:
            guard let defaultSourceURL = expectedSourceURL(
                for: browser,
                homeDirectoryURL: homeDirectoryURL
            ) else {
                return LoadResult(profiles: [defaultChromiumProfile()], issue: nil)
            }

            let localStateURL = authorizedSourceURL ?? defaultSourceURL
            let data: Data
            do {
                data = try readData(
                    at: localStateURL,
                    usesSecurityScope: authorizedSourceURL != nil
                )
            } catch {
                return LoadResult(
                    profiles: [defaultChromiumProfile()],
                    issue: loadIssue(for: browser, sourceURL: localStateURL, error: error)
                )
            }

            let parsedProfiles = chromiumProfiles(fromLocalStateData: data)
            guard !parsedProfiles.isEmpty else {
                return LoadResult(
                    profiles: [defaultChromiumProfile()],
                    issue: MeetingBrowserProfileLoadIssue(
                        browser: browser,
                        reason: .invalidData,
                        sourcePath: localStateURL.path,
                        technicalDescription: "The profile info cache was missing or empty."
                    )
                )
            }
            return LoadResult(profiles: parsedProfiles, issue: nil)
        case .firefox:
            guard let defaultSourceURL = expectedSourceURL(
                for: browser,
                homeDirectoryURL: homeDirectoryURL
            ) else {
                return LoadResult(profiles: [defaultFirefoxProfile()], issue: nil)
            }

            let profilesURL = authorizedSourceURL ?? defaultSourceURL
            let data: Data
            do {
                data = try readData(
                    at: profilesURL,
                    usesSecurityScope: authorizedSourceURL != nil
                )
            } catch {
                return LoadResult(
                    profiles: [defaultFirefoxProfile()],
                    issue: loadIssue(for: browser, sourceURL: profilesURL, error: error)
                )
            }

            let parsedProfiles = firefoxProfiles(fromProfilesIniData: data)
            guard !parsedProfiles.isEmpty else {
                return LoadResult(
                    profiles: [defaultFirefoxProfile()],
                    issue: MeetingBrowserProfileLoadIssue(
                        browser: browser,
                        reason: .invalidData,
                        sourcePath: profilesURL.path,
                        technicalDescription: "No Firefox profile sections were found."
                    )
                )
            }
            return LoadResult(profiles: parsedProfiles, issue: nil)
        case .none:
            return LoadResult(
                profiles: [MeetingBrowserProfileOption.automatic(for: browser)],
                issue: nil
            )
        }
    }

    private static func readData(
        at sourceURL: URL,
        usesSecurityScope: Bool
    ) throws -> Data {
        let didStartAccessing = usesSecurityScope
            ? sourceURL.startAccessingSecurityScopedResource()
            : false
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        return try Data(contentsOf: sourceURL)
    }

    private static func loadIssue(
        for browser: MeetingBrowserKind,
        sourceURL: URL,
        error: Error
    ) -> MeetingBrowserProfileLoadIssue {
        let nsError = error as NSError
        let reason: MeetingBrowserProfileLoadIssue.Reason

        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.fileReadNoPermission.rawValue {
            reason = .accessDenied
        } else if nsError.domain == NSPOSIXErrorDomain,
                  nsError.code == Int(EACCES) || nsError.code == Int(EPERM) {
            reason = .accessDenied
        } else if nsError.domain == NSCocoaErrorDomain,
                  nsError.code == CocoaError.fileReadNoSuchFile.rawValue {
            reason = .sourceMissing
        } else {
            reason = .unreadable
        }

        return MeetingBrowserProfileLoadIssue(
            browser: browser,
            reason: reason,
            sourcePath: sourceURL.path,
            technicalDescription: nsError.localizedDescription
        )
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
