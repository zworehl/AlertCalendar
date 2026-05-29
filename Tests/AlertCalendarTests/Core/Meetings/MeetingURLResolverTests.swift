import Foundation
import EventKit
import XCTest
@testable import AlertCalendar

final class MeetingURLResolverTests: XCTestCase {
    func testBestMeetingURLPrefersZoomMeetingOverZoomAsset() {
        let zoomAssetURL = URL(string: "https://st1.zoom.us/static/6.3.1/image/new/ZoomLogo_112_112.png")!
        let zoomMeetingURL = URL(string: "https://us02web.zoom.us/j/123456789?pwd=secret")!

        let bestURL = MeetingURLResolver.bestMeetingURL(from: [zoomAssetURL, zoomMeetingURL])

        XCTAssertEqual(bestURL, zoomMeetingURL)
    }

    func testIsKnownMeetingURLRejectsZoomAssetLinks() {
        let zoomAssetURL = URL(string: "https://st1.zoom.us/static/6.3.1/image/new/ZoomLogo_112_112.png")!

        XCTAssertFalse(MeetingURLResolver.isKnownMeetingURL(zoomAssetURL))
    }

    func testResolvedMeetingURLExtractsEmbeddedZoomMeetingFromRedirectURL() {
        let wrappedURL = URL(string: "https://www.google.com/url?q=https%3A%2F%2Fus02web.zoom.us%2Fj%2F123456789%3Fpwd%3Dsecret&sa=D")!
        let expected = URL(string: "https://us02web.zoom.us/j/123456789?pwd=secret")!

        XCTAssertEqual(MeetingURLResolver.resolvedMeetingURL(from: wrappedURL), expected)
    }

    func testBestMeetingURLResolvesTeamsMeetingFromOutlookSafeLink() {
        let teamsURL = URL(
            string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%22tenant%22%2c%22Oid%22%3a%22organizer%22%7d"
        )!
        var components = URLComponents(string: "https://nam12.safelinks.protection.outlook.com/")!
        components.queryItems = [
            URLQueryItem(name: "url", value: teamsURL.absoluteString),
            URLQueryItem(name: "data", value: "tracking"),
        ]

        let bestURL = MeetingURLResolver.bestMeetingURL(from: [components.url!])

        XCTAssertEqual(bestURL?.host, teamsURL.host)
        XCTAssertTrue(bestURL?.path.contains("/l/meetup-join/") ?? false)
        XCTAssertTrue(bestURL?.absoluteString.contains("meeting_abc") ?? false)
        XCTAssertTrue(bestURL?.absoluteString.contains("context=") ?? false)
    }

    func testAllURLsDecodesHTMLEscapedTeamsLinks() {
        let text = """
        <a href="https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%22tenant%22%7d&amp;anon=true">Join Microsoft Teams Meeting</a>
        """

        let teamsURL = MeetingURLResolver.allURLs(in: text).first {
            $0.host == "teams.microsoft.com"
                && $0.absoluteString.contains("meetup-join")
        }

        XCTAssertNotNil(teamsURL)
        XCTAssertFalse(teamsURL?.absoluteString.contains("amp;") ?? true)
    }

    func testEventMeetingURLResolverUsesEventKitConferenceURL() {
        let event = EKEvent(eventStore: EKEventStore())
        let teamsURL = URL(
            string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%22tenant%22%2c%22Oid%22%3a%22organizer%22%7d"
        )!
        let eventObject = event as NSObject
        let selector = NSSelectorFromString("setConferenceURL:")

        XCTAssertTrue(eventObject.responds(to: selector))
        eventObject.perform(selector, with: teamsURL as NSURL)

        XCTAssertEqual(EventMeetingURLResolver.meetingURL(for: event), teamsURL)
    }
}
