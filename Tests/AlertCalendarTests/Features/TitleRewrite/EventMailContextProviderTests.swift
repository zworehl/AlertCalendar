import XCTest
@testable import AlertCalendar

final class EventMailContextProviderTests: XCTestCase {
    func testRequestPrefersPortableIdentifiersOverFullTitle() {
        let request = EventMailContextRequest(
            title: "Connect with Jonn for defect : WHD-15218",
            description: "Follow up on case #1842",
            participantEmailAddresses: []
        )

        XCTAssertEqual(request.searchTerms, ["WHD-15218", "#1842"])
    }

    func testRequestUsesDistinctiveExactTitleWhenNoIdentifierExists() {
        let request = EventMailContextRequest(
            title: "Quarterly product migration readiness review",
            description: nil,
            participantEmailAddresses: []
        )

        XCTAssertEqual(
            request.searchTerms,
            ["Quarterly product migration readiness review"]
        )
    }

    func testRequestDoesNotSearchMailForShortGenericTitle() {
        let request = EventMailContextRequest(
            title: "Team meeting",
            description: nil,
            participantEmailAddresses: []
        )

        XCTAssertTrue(request.searchTerms.isEmpty)
    }

    func testProviderReturnsBoundedRedactedRelevantContext() async {
        let provider = AppleMailEventContextProvider { _ in
            [
                .init(
                    subject: "WHD-15218 assigned to user@example.com",
                    content: "Join https://example.com/private\nRQA My Account Page not loading for authenticated users\nMeeting ID: 123 456 789 012"
                ),
            ]
        }
        let contexts = await provider.contexts(
            for: EventMailContextRequest(
                title: "Connect with Jonn for defect : WHD-15218",
                description: nil,
                participantEmailAddresses: ["user@example.com"]
            )
        )

        let context = try? XCTUnwrap(contexts.first)
        XCTAssertTrue(context?.contains("WHD-15218 assigned to [email]") == true)
        XCTAssertTrue(context?.contains("RQA My Account Page") == true)
        XCTAssertFalse(context?.contains("https://example.com/private") == true)
        XCTAssertFalse(context?.contains("123 456 789 012") == true)
    }
}
