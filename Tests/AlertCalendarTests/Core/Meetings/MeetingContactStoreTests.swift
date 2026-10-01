import Contacts
import XCTest
@testable import AlertCalendar

final class MeetingContactStoreTests: XCTestCase {
    func testUsesFullContactPhotoWhenThumbnailIsUnavailable() {
        let contact = CNMutableContact()
        contact.givenName = "Ari"
        contact.imageData = Data([1, 2, 3])
        let resolved = SystemMeetingContactStore.resolvedContact(
            from: [contact], fallbackEmailAddress: "ari@example.com"
        )

        XCTAssertEqual(resolved?.displayText, "Ari")
        XCTAssertEqual(resolved?.avatarImageData, contact.imageData)
    }

    func testPrefersMatchingContactWithPhotoOverDuplicateWithoutPhoto() {
        let first = CNMutableContact()
        first.givenName = "Ari"
        let withPhoto = CNMutableContact()
        withPhoto.givenName = "Ari"
        withPhoto.familyName = "Ramos"
        withPhoto.imageData = Data([1, 2, 3])
        let resolved = SystemMeetingContactStore.resolvedContact(
            from: [first, withPhoto], fallbackEmailAddress: "ari@example.com"
        )

        XCTAssertEqual(resolved?.displayText, "Ari Ramos")
        XCTAssertEqual(resolved?.avatarImageData, withPhoto.imageData)
    }

    func testContactWithoutPhotoStillResolvesName() {
        let contact = CNMutableContact()
        contact.nickname = "Ari"
        let resolved = SystemMeetingContactStore.resolvedContact(
            from: [contact], fallbackEmailAddress: "ari@example.com"
        )

        XCTAssertEqual(resolved?.displayText, "Ari")
        XCTAssertNil(resolved?.avatarImageData)
        XCTAssertNil(SystemMeetingContactStore.resolvedContact(from: [], fallbackEmailAddress: "ari@example.com"))
    }
}
