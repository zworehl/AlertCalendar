import Foundation
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
}
