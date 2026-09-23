import Foundation

enum MeetingService: Equatable, Sendable {
    case googleMeet
    case zoom
    case microsoftTeams
    case webex
    case whereby
    case jitsi
    case amazonChime
    case generic

    var title: String {
        switch self {
        case .googleMeet:
            return "Meet"
        case .zoom:
            return "Zoom"
        case .microsoftTeams:
            return "Microsoft Teams"
        case .webex:
            return "Webex"
        case .whereby:
            return "Whereby"
        case .jitsi:
            return "Jitsi"
        case .amazonChime:
            return "Amazon Chime"
        case .generic:
            return "Meeting Link"
        }
    }

    var iconAssetName: String? {
        switch self {
        case .googleMeet:
            return "meeting-service-google-meet"
        case .zoom:
            return "meeting-service-zoom"
        case .microsoftTeams:
            return "meeting-service-microsoft-teams"
        case .webex:
            return "meeting-service-webex"
        case .whereby:
            return "meeting-service-whereby"
        case .jitsi:
            return "meeting-service-jitsi"
        case .amazonChime:
            return "meeting-service-amazon-chime"
        case .generic:
            return nil
        }
    }

    static func resolve(from url: URL) -> MeetingService {
        let host = (url.host ?? "").lowercased()
        let scheme = (url.scheme ?? "").lowercased()
        let absolute = url.absoluteString.lowercased()

        if host.contains("meet.google.") || host == "g.co" {
            return .googleMeet
        }
        if host.contains("zoom.") || host.contains("us02web.zoom.") {
            return .zoom
        }
        if scheme == "msteams"
            || scheme == "microsoftteams"
            || host.contains("teams.")
            || host.contains("teams.microsoft.")
            || host.contains("teams.live.")
            || host.contains("teams.office.")
            || host.contains("aka.ms")
            || host.contains("microsoftteams.")
            || host.contains("teams.ms")
            || absolute.contains("meetup-join")
            || absolute.contains("teams.microsoft.com")
            || absolute.contains("teams.live.com")
            || absolute.contains("teams.office.com") {
            return .microsoftTeams
        }
        if host.contains("webex.") {
            return .webex
        }
        if host.contains("whereby.") {
            return .whereby
        }
        if host.contains("jitsi.") || host.contains("meet.jit.si") {
            return .jitsi
        }
        if host.contains("chime.aws") || host.contains("amazonchime.") {
            return .amazonChime
        }

        return .generic
    }
}
