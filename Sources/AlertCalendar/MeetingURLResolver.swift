import Foundation

enum MeetingURLResolver {
    private static let assetExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "ico", "tif", "tiff", "heic", "avif",
    ]

    private static let assetPathFragments = [
        "/static/",
        "/image/",
        "/images/",
        "/img/",
        "/logo",
        "/logos/",
        "/icon",
        "/icons/",
        "/avatar",
        "/thumbnail",
        "/thumb/",
        "/brand/",
        "/branding/",
        "/assets/",
    ]

    private static let assetKeywords = [
        "logo",
        "icon",
        "favicon",
        "sprite",
        "avatar",
        "thumbnail",
        "branding",
    ]

    static func bestMeetingURL(from candidates: [URL]) -> URL? {
        var bestURL: URL?
        var bestScore = Int.min

        for candidate in candidates {
            for resolved in resolvedMeetingURLCandidates(from: candidate) {
                let score = meetingURLScore(resolved)
                guard score > bestScore else { continue }
                bestScore = score
                bestURL = resolved
            }
        }

        return bestURL
    }

    static func allURLs(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(location: 0, length: text.utf16.count)
        return detector.matches(in: text, options: [], range: range).compactMap(\.url)
    }

    static func resolvedMeetingURL(from url: URL) -> URL? {
        resolvedMeetingURLCandidates(from: url).first
    }

    static func resolvedMeetingURLCandidates(from url: URL) -> [URL] {
        var results: [URL] = []
        var visited: Set<String> = []
        collectMeetingURLCandidates(from: url, results: &results, visited: &visited)
        return results
    }

    static func meetingURLScore(_ url: URL) -> Int {
        guard isKnownMeetingURL(url) else { return Int.min }

        let host = (url.host ?? "").lowercased()
        let scheme = (url.scheme ?? "").lowercased()
        let absolute = url.absoluteString.lowercased()
        let path = url.path.lowercased()
        var score = 0

        if scheme == "https" { score += 5 }

        if scheme == "msteams" || scheme == "microsoftteams" {
            score += 160
        }
        if absolute.contains("/l/meetup-join/") || absolute.contains("meetup-join") {
            score += 130
        }
        if absolute.contains("meetingid=") || absolute.contains("context=") {
            score += 25
        }
        if host.contains("teams.microsoft.")
            || host.contains("teams.live.")
            || host.contains("teams.office.")
            || host.contains("microsoftteams.")
            || host.contains("teams.ms") {
            score += 80
        }

        if host.contains("aka.ms") { score -= 70 }
        if absolute.contains("join-a-meeting") { score -= 80 }

        if host.contains("meet.google.") || host.contains("g.co") { score += 70 }
        if host.contains("zoom.") { score += 70 }
        if host.contains("webex.") { score += 70 }
        if host.contains("whereby.") { score += 70 }
        if host.contains("jitsi.") || host.contains("meet.jit.si") { score += 70 }
        if host.contains("chime.aws") || host.contains("amazonchime.") { score += 70 }

        if host.contains("zoom.") {
            if path.contains("/j/") || path.contains("/w/") || path.contains("/wc/") || path.contains("/my/") {
                score += 180
            }
            if absolute.contains("pwd=") || absolute.contains("zak=") || absolute.contains("confno=") {
                score += 35
            }
        }

        if host.contains("meet.google.") {
            let meetingCode = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if meetingCode.count >= 10, meetingCode.contains("-") {
                score += 180
            }
        }

        if host.contains("webex."),
           path.contains("/meet/") || path.contains("/join/") || path.contains("/webappng/") {
            score += 180
        }

        if host.contains("whereby.") || host.contains("jitsi.") || host.contains("meet.jit.si") {
            let roomPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !roomPath.isEmpty {
                score += 140
            }
        }

        if host.contains("chime.aws") || host.contains("amazonchime."),
           path.contains("/meetings/") || path.contains("/calls/") {
            score += 140
        }

        return score
    }

    static func isKnownMeetingURL(_ url: URL) -> Bool {
        guard !isMeetingAssetURL(url) else { return false }

        let host = (url.host ?? "").lowercased()
        let scheme = (url.scheme ?? "").lowercased()
        let absolute = url.absoluteString.lowercased()

        if host.contains("meet.google.") { return true }
        if host.contains("g.co") { return true }
        if host.contains("zoom.") { return true }
        if scheme == "msteams" || scheme == "microsoftteams" { return true }
        if host.contains("teams.")
            || host.contains("teams.microsoft.")
            || host.contains("teams.live.")
            || host.contains("teams.office.")
            || host.contains("microsoftteams.")
            || host.contains("teams.ms")
            || absolute.contains("meetup-join")
            || absolute.contains("teams.microsoft.com")
            || absolute.contains("teams.live.com")
            || absolute.contains("teams.office.com") { return true }
        if host.contains("aka.ms") { return true }
        if host.contains("webex.") { return true }
        if host.contains("whereby.") { return true }
        if host.contains("jitsi.") || host.contains("meet.jit.si") { return true }
        if host.contains("chime.aws") || host.contains("amazonchime.") { return true }
        return false
    }

    private static func collectMeetingURLCandidates(from url: URL, results: inout [URL], visited: inout Set<String>) {
        let key = url.absoluteString
        guard visited.insert(key).inserted else { return }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            for queryItem in queryItems {
                guard let rawValue = queryItem.value else { continue }
                let decoded = rawValue.removingPercentEncoding ?? rawValue

                if let embeddedURL = URL(string: decoded) {
                    collectMeetingURLCandidates(from: embeddedURL, results: &results, visited: &visited)
                }

                for embeddedTextURL in allURLs(in: decoded) {
                    collectMeetingURLCandidates(from: embeddedTextURL, results: &results, visited: &visited)
                }
            }
        }

        if isKnownMeetingURL(url) {
            results.append(url)
        }
    }

    private static func isMeetingAssetURL(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        let absolute = url.absoluteString.lowercased()
        let path = url.path.lowercased()
        let pathExtension = URL(fileURLWithPath: path).pathExtension.lowercased()

        if assetExtensions.contains(pathExtension) {
            return true
        }

        if assetPathFragments.contains(where: { path.contains($0) }) {
            return true
        }

        if isKnownMeetingHost(host), assetKeywords.contains(where: { absolute.contains($0) }) {
            return true
        }

        return false
    }

    private static func isKnownMeetingHost(_ host: String) -> Bool {
        host.contains("meet.google.")
            || host.contains("g.co")
            || host.contains("zoom.")
            || host.contains("teams.")
            || host.contains("teams.microsoft.")
            || host.contains("teams.live.")
            || host.contains("teams.office.")
            || host.contains("microsoftteams.")
            || host.contains("teams.ms")
            || host.contains("aka.ms")
            || host.contains("webex.")
            || host.contains("whereby.")
            || host.contains("jitsi.")
            || host.contains("meet.jit.si")
            || host.contains("chime.aws")
            || host.contains("amazonchime.")
    }
}
