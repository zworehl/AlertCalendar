import AppKit
import XCTest
@testable import AlertCalendar

final class MeetingServiceTests: XCTestCase {
    func testMeetingServiceResolutionMatchesSupportedMeetingProviders() {
        XCTAssertEqual(
            MeetingService.resolve(from: URL(string: "https://meet.google.com/abc-defg-hij")!),
            .googleMeet
        )
        XCTAssertEqual(
            MeetingService.resolve(from: URL(string: "https://us02web.zoom.us/j/123456789")!),
            .zoom
        )
        XCTAssertEqual(
            MeetingService.resolve(from: URL(string: "https://teams.microsoft.com/l/meetup-join/meeting")!),
            .microsoftTeams
        )
        XCTAssertEqual(
            MeetingService.resolve(from: URL(string: "https://example.com/meeting")!),
            .generic
        )
    }

    @MainActor
    func testKnownMeetingServiceIconsKeepTheExistingTwelvePointSize() {
        let size: CGFloat = MenuMarkerMetrics.symbolSize
        let services: [MeetingService] = [
            .googleMeet,
            .zoom,
            .microsoftTeams,
            .webex,
            .whereby,
            .jitsi,
            .amazonChime,
        ]

        for service in services {
            let image = MeetingServiceIconProvider.image(for: service, size: size)
            XCTAssertEqual(image?.size, NSSize(width: size, height: size), service.title)
        }
    }
}
