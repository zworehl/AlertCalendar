import Contacts
import XCTest
@testable import AlertCalendar

final class MeetingContactResolverTests: XCTestCase {
    func testResolvesOrganizerAndAttendeePhotosUsingNormalizedEmail() async {
        let imageData = Data([1, 2, 3])
        let store = StubMeetingContactStore(contact: ResolvedMeetingContact(
            displayText: "Ari Ramos", avatarImageData: imageData
        ))
        let resolver = MeetingContactResolver(contactStore: store, notificationCenter: NotificationCenter())
        let organizer = await resolver.resolve(organizer: MeetingOrganizer(
            displayText: "ari@example.com", emailAddress: " ARI@example.com "
        ))
        let attendees = await resolver.resolve(attendees: [attendee()])
        let lookupEmails = await store.lookupEmails

        XCTAssertEqual(organizer?.displayText, "Ari Ramos")
        XCTAssertEqual(organizer?.avatarImageData, imageData)
        XCTAssertEqual(attendees.first?.displayText, "Ari Ramos")
        XCTAssertEqual(attendees.first?.avatarImageData, imageData)
        XCTAssertEqual(attendees.first?.response, .accepted)
        XCTAssertEqual(lookupEmails, ["ari@example.com"])
    }

    func testContactChangeRefreshesCachedPhoto() async {
        let store = StubMeetingContactStore(contact: ResolvedMeetingContact(
            displayText: "Ari", avatarImageData: Data([1])
        ))
        let center = NotificationCenter()
        let resolver = MeetingContactResolver(contactStore: store, notificationCenter: center)
        let original = await resolver.resolve(attendees: [attendee()])
        await store.setContact(ResolvedMeetingContact(displayText: "Ari", avatarImageData: Data([2])))
        await notifyContactChange(center)
        let refreshed = await resolver.resolve(attendees: [attendee()])

        XCTAssertEqual(original.first?.avatarImageData, Data([1]))
        XCTAssertEqual(refreshed.first?.avatarImageData, Data([2]))
    }

    func testContactChangeRetriesPreviouslyMissingContact() async {
        let store = StubMeetingContactStore(contact: nil)
        let center = NotificationCenter()
        let resolver = MeetingContactResolver(contactStore: store, notificationCenter: center)
        let original = await resolver.resolve(attendees: [attendee()])
        await store.setContact(ResolvedMeetingContact(displayText: "Ari", avatarImageData: Data([2])))
        await notifyContactChange(center)
        let refreshed = await resolver.resolve(attendees: [attendee()])

        XCTAssertNil(original.first?.avatarImageData)
        XCTAssertEqual(refreshed.first?.avatarImageData, Data([2]))
    }

    func testTemporaryLookupFailureIsRetried() async {
        let store = StubMeetingContactStore(contact: ResolvedMeetingContact(
            displayText: "Ari", avatarImageData: Data([2])
        ))
        await store.failNextLookup()
        let resolver = MeetingContactResolver(contactStore: store, notificationCenter: NotificationCenter())
        let original = await resolver.resolve(attendees: [attendee()])
        let retry = await resolver.resolve(attendees: [attendee()])

        XCTAssertNil(original.first?.avatarImageData)
        XCTAssertEqual(retry.first?.avatarImageData, Data([2]))
    }

    func testRevokingAccessDiscardsCachedContactAndGrantingAccessReloadsIt() async {
        let store = StubMeetingContactStore(contact: ResolvedMeetingContact(
            displayText: "Ari", avatarImageData: Data([1])
        ))
        let resolver = MeetingContactResolver(contactStore: store, notificationCenter: NotificationCenter())
        _ = await resolver.resolve(attendees: [attendee()])
        await store.setAuthorizationStatus(.denied)
        let denied = await resolver.resolve(attendees: [attendee()])
        await store.setContact(ResolvedMeetingContact(displayText: "Ari", avatarImageData: Data([2])))
        await store.setAuthorizationStatus(.authorized)
        let allowed = await resolver.resolve(attendees: [attendee()])
        let lookupEmails = await store.lookupEmails

        XCTAssertEqual(denied, [attendee()])
        XCTAssertEqual(allowed.first?.avatarImageData, Data([2]))
        XCTAssertEqual(lookupEmails.count, 2)
    }

    func testUnavailableContactPreservesExistingParticipantPhoto() async {
        let store = StubMeetingContactStore(contact: nil)
        let resolver = MeetingContactResolver(contactStore: store, notificationCenter: NotificationCenter())
        let participant = attendee(avatarImageData: Data([4]))
        let resolved = await resolver.resolve(attendees: [participant])

        XCTAssertEqual(resolved, [participant])
    }

    private func notifyContactChange(_ center: NotificationCenter) async {
        let changed = expectation(description: "Contact cache invalidated before preview refresh")
        let observer = center.addObserver(
            forName: .alertCalendarMeetingContactsDidChange, object: nil, queue: nil
        ) { _ in
            changed.fulfill()
        }
        defer { center.removeObserver(observer) }
        center.post(name: .CNContactStoreDidChange, object: nil)
        await fulfillment(of: [changed], timeout: 2)
    }

    private func attendee(avatarImageData: Data? = nil) -> MeetingAttendee {
        MeetingAttendee(
            id: "ari@example.com", displayText: "ari@example.com",
            emailAddress: "ari@example.com", response: .accepted, avatarImageData: avatarImageData
        )
    }
}

private actor StubMeetingContactStore: MeetingContactStoreProviding {
    private var status: CNAuthorizationStatus = .authorized
    private var resolvedContact: ResolvedMeetingContact?
    private var shouldFailNextLookup = false
    private(set) var lookupEmails: [String] = []

    init(contact: ResolvedMeetingContact?) {
        resolvedContact = contact
    }

    func authorizationStatus() -> CNAuthorizationStatus { status }
    func requestAccess() -> Bool { status == .authorized }

    func contact(matchingEmailAddress emailAddress: String) throws -> ResolvedMeetingContact? {
        lookupEmails.append(emailAddress)
        if shouldFailNextLookup {
            shouldFailNextLookup = false
            throw NSError(domain: "MeetingContactResolverTests", code: 1)
        }
        return resolvedContact
    }

    func setContact(_ contact: ResolvedMeetingContact?) { resolvedContact = contact }
    func setAuthorizationStatus(_ status: CNAuthorizationStatus) { self.status = status }
    func failNextLookup() { shouldFailNextLookup = true }
}
