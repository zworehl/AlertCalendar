import Contacts
import Foundation

protocol MeetingContactStoreProviding: Sendable {
    func authorizationStatus() async -> CNAuthorizationStatus
    func requestAccess() async -> Bool
    func contact(matchingEmailAddress emailAddress: String) async throws -> ResolvedMeetingContact?
}

actor SystemMeetingContactStore: MeetingContactStoreProviding {
    private let contactStore = CNContactStore()
    private let contactKeysToFetch: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactNicknameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
        CNContactImageDataKey as CNKeyDescriptor,
    ]

    func authorizationStatus() -> CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            contactStore.requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func contact(matchingEmailAddress emailAddress: String) throws -> ResolvedMeetingContact? {
        let contacts = try contactStore.unifiedContacts(
            matching: CNContact.predicateForContacts(matchingEmailAddress: emailAddress),
            keysToFetch: contactKeysToFetch
        )
        return Self.resolvedContact(from: contacts, fallbackEmailAddress: emailAddress)
    }

    nonisolated static func resolvedContact(
        from contacts: [CNContact],
        fallbackEmailAddress: String
    ) -> ResolvedMeetingContact? {
        // Linked or duplicate records can share an email; prefer a record with a photo.
        guard let contact = contacts.first(where: { avatarImageData(for: $0) != nil }) ?? contacts.first else {
            return nil
        }

        let displayText = AlertCalendarString.trimmedNonEmpty(
            CNContactFormatter.string(from: contact, style: .fullName)
        ) ?? AlertCalendarString.trimmedNonEmpty(contact.nickname)
            ?? AlertCalendarString.trimmedNonEmpty(contact.organizationName)
            ?? fallbackEmailAddress

        return ResolvedMeetingContact(
            displayText: displayText,
            avatarImageData: avatarImageData(for: contact)
        )
    }

    private nonisolated static func avatarImageData(for contact: CNContact) -> Data? {
        [contact.thumbnailImageData, contact.imageData].compactMap { $0 }.first { !$0.isEmpty }
    }
}
