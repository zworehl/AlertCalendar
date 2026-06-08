import AppKit
import Foundation

enum MeetingBrowserKind: String, CaseIterable, Codable, Identifiable {
    case chrome
    case edge
    case brave
    case vivaldi
    case chromium
    case safari
    case firefox
    case firefoxDeveloperEdition
    case librewolf
    case floorp
    case zen
    case arc
    case opera
    case duckDuckGo
    case orion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chrome:
            return "Chrome"
        case .edge:
            return "Microsoft Edge"
        case .brave:
            return "Brave"
        case .vivaldi:
            return "Vivaldi"
        case .chromium:
            return "Chromium"
        case .safari:
            return "Safari"
        case .firefox:
            return "Firefox"
        case .firefoxDeveloperEdition:
            return "Firefox Developer Edition"
        case .librewolf:
            return "LibreWolf"
        case .floorp:
            return "Floorp"
        case .zen:
            return "Zen"
        case .arc:
            return "Arc"
        case .opera:
            return "Opera"
        case .duckDuckGo:
            return "DuckDuckGo"
        case .orion:
            return "Orion"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .chrome:
            return "com.google.Chrome"
        case .edge:
            return "com.microsoft.edgemac"
        case .brave:
            return "com.brave.Browser"
        case .vivaldi:
            return "com.vivaldi.Vivaldi"
        case .chromium:
            return "org.chromium.Chromium"
        case .safari:
            return "com.apple.Safari"
        case .firefox:
            return "org.mozilla.firefox"
        case .firefoxDeveloperEdition:
            return "org.mozilla.firefoxdeveloperedition"
        case .librewolf:
            return "io.gitlab.librewolf-community"
        case .floorp:
            return "one.ablaze.floorp"
        case .zen:
            return "app.zen-browser.zen"
        case .arc:
            return "company.thebrowser.Browser"
        case .opera:
            return "com.operasoftware.Opera"
        case .duckDuckGo:
            return "com.duckduckgo.macos.browser"
        case .orion:
            return "com.kagi.kagimacOS"
        }
    }

    var fallbackApplicationPath: String {
        switch self {
        case .chrome:
            return "/Applications/Google Chrome.app"
        case .edge:
            return "/Applications/Microsoft Edge.app"
        case .brave:
            return "/Applications/Brave Browser.app"
        case .vivaldi:
            return "/Applications/Vivaldi.app"
        case .chromium:
            return "/Applications/Chromium.app"
        case .safari:
            return "/Applications/Safari.app"
        case .firefox:
            return "/Applications/Firefox.app"
        case .firefoxDeveloperEdition:
            return "/Applications/Firefox Developer Edition.app"
        case .librewolf:
            return "/Applications/LibreWolf.app"
        case .floorp:
            return "/Applications/Floorp.app"
        case .zen:
            return "/Applications/Zen.app"
        case .arc:
            return "/Applications/Arc.app"
        case .opera:
            return "/Applications/Opera.app"
        case .duckDuckGo:
            return "/Applications/DuckDuckGo.app"
        case .orion:
            return "/Applications/Orion.app"
        }
    }

    var executableName: String {
        switch self {
        case .chrome:
            return "Google Chrome"
        case .edge:
            return "Microsoft Edge"
        case .brave:
            return "Brave Browser"
        case .vivaldi:
            return "Vivaldi"
        case .chromium:
            return "Chromium"
        case .safari:
            return "Safari"
        case .firefox, .firefoxDeveloperEdition:
            return "firefox"
        case .librewolf:
            return "librewolf"
        case .floorp:
            return "floorp"
        case .zen:
            return "zen"
        case .arc:
            return "Arc"
        case .opera:
            return "Opera"
        case .duckDuckGo:
            return "DuckDuckGo"
        case .orion:
            return "Orion"
        }
    }

    var profileFamily: MeetingBrowserProfileFamily {
        switch self {
        case .chrome, .edge, .brave, .vivaldi, .chromium:
            return .chromium
        case .firefox, .firefoxDeveloperEdition, .librewolf, .floorp, .zen:
            return .firefox
        case .safari, .arc, .opera, .duckDuckGo, .orion:
            return .none
        }
    }

    var chromiumLocalStateRelativePath: String? {
        switch self {
        case .chrome:
            return "Library/Application Support/Google/Chrome/Local State"
        case .edge:
            return "Library/Application Support/Microsoft Edge/Local State"
        case .brave:
            return "Library/Application Support/BraveSoftware/Brave-Browser/Local State"
        case .vivaldi:
            return "Library/Application Support/Vivaldi/Local State"
        case .chromium:
            return "Library/Application Support/Chromium/Local State"
        case .safari, .firefox, .firefoxDeveloperEdition, .librewolf, .floorp, .zen, .arc, .opera, .duckDuckGo, .orion:
            return nil
        }
    }

    var firefoxProfilesIniRelativePath: String? {
        switch self {
        case .firefox, .firefoxDeveloperEdition:
            return "Library/Application Support/Firefox/profiles.ini"
        case .librewolf:
            return "Library/Application Support/LibreWolf/profiles.ini"
        case .floorp:
            return "Library/Application Support/Floorp/profiles.ini"
        case .zen:
            return "Library/Application Support/Zen/profiles.ini"
        case .chrome, .edge, .brave, .vivaldi, .chromium, .safari, .arc, .opera, .duckDuckGo, .orion:
            return nil
        }
    }
}

enum MeetingBrowserProfileFamily {
    case chromium
    case firefox
    case none
}

struct MeetingBrowserRoute: Codable, Equatable, Hashable {
    static let automaticProfileID = "automatic"
    static let defaultChromeProfileID = "Default"
    static let defaultFirefoxProfileID = "default-release"

    var browser: MeetingBrowserKind
    var profileID: String

    init(browser: MeetingBrowserKind, profileID: String = Self.automaticProfileID) {
        self.browser = browser
        self.profileID = profileID
    }

    static let defaultRoute = MeetingBrowserRoute(browser: .safari)

    var normalized: MeetingBrowserRoute {
        var route = self
        switch route.browser {
        case .safari, .arc, .opera, .duckDuckGo, .orion:
            route.profileID = Self.automaticProfileID
        case .chrome, .edge, .brave, .vivaldi, .chromium:
            let trimmedProfileID = route.profileID.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedProfileID.isEmpty || trimmedProfileID == Self.automaticProfileID {
                route.profileID = Self.defaultChromeProfileID
            } else {
                route.profileID = trimmedProfileID
            }
        case .firefox, .firefoxDeveloperEdition, .librewolf, .floorp, .zen:
            let trimmedProfileID = route.profileID.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedProfileID.isEmpty || trimmedProfileID == Self.automaticProfileID {
                route.profileID = Self.defaultFirefoxProfileID
            } else {
                route.profileID = trimmedProfileID
            }
        }
        return route
    }
}

enum MeetingBrowserCatalog {
    static func installedBrowsers() -> [MeetingBrowserKind] {
        MeetingBrowserKind.allCases.filter { applicationURL(for: $0) != nil }
    }

    static func applicationURL(for browser: MeetingBrowserKind) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier) {
            return url
        }

        let fallbackURL = URL(fileURLWithPath: browser.fallbackApplicationPath)
        if FileManager.default.fileExists(atPath: fallbackURL.path) {
            return fallbackURL
        }

        let userFallbackURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")
            .appendingPathComponent(URL(fileURLWithPath: browser.fallbackApplicationPath).lastPathComponent)
        guard FileManager.default.fileExists(atPath: userFallbackURL.path) else { return nil }
        return userFallbackURL
    }
}

struct MeetingBrowserProfileOption: Identifiable, Equatable {
    let id: String
    let displayName: String
    let detailText: String
    let isDefault: Bool

    static func automatic(for browser: MeetingBrowserKind) -> MeetingBrowserProfileOption {
        MeetingBrowserProfileOption(
            id: MeetingBrowserRoute.automaticProfileID,
            displayName: "Automatic",
            detailText: browser.title,
            isDefault: true
        )
    }
}

struct CalendarMeetingBrowserRule: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var calendarIDs: Set<String>
    var route: MeetingBrowserRoute
    var isEnabled: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        calendarIDs: Set<String>,
        route: MeetingBrowserRoute,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.calendarIDs = calendarIDs
        self.route = route
        self.isEnabled = isEnabled
    }
}

struct MeetingBrowserRoutingSettings: Codable, Equatable {
    var defaultRoute: MeetingBrowserRoute
    var rules: [CalendarMeetingBrowserRule]

    static let defaults = MeetingBrowserRoutingSettings(
        defaultRoute: .defaultRoute,
        rules: []
    )

    var normalized: MeetingBrowserRoutingSettings {
        normalized(availableCalendarIDs: nil)
    }

    func normalized(availableCalendarIDs: Set<String>?) -> MeetingBrowserRoutingSettings {
        let normalizedRules = rules.compactMap { rule -> CalendarMeetingBrowserRule? in
            var normalizedRule = rule
            normalizedRule.name = normalizedRule.name.trimmingCharacters(in: .whitespacesAndNewlines)
            normalizedRule.route = normalizedRule.route.normalized

            if let availableCalendarIDs {
                normalizedRule.calendarIDs = normalizedRule.calendarIDs.intersection(availableCalendarIDs)
            }

            guard !normalizedRule.calendarIDs.isEmpty else { return nil }
            return normalizedRule
        }

        return MeetingBrowserRoutingSettings(
            defaultRoute: defaultRoute.normalized,
            rules: normalizedRules
        )
    }
}

enum MeetingBrowserRouting {
    static func route(
        for calendarID: String?,
        settings: MeetingBrowserRoutingSettings
    ) -> MeetingBrowserRoute {
        guard let calendarID else {
            return settings.defaultRoute.normalized
        }

        let normalizedSettings = settings.normalized
        return normalizedSettings.rules.first { rule in
            rule.isEnabled && rule.calendarIDs.contains(calendarID)
        }?.route.normalized ?? normalizedSettings.defaultRoute.normalized
    }
}

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
