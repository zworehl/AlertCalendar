import Contacts
import Foundation

struct ResolvedMeetingContact: Equatable, Sendable {
    let displayText: String?
    let avatarImageData: Data?
}

actor MeetingContactResolver {
    static let shared = MeetingContactResolver()

    private let contactStore = CNContactStore()
    private var cachedContactsByEmail: [String: ResolvedMeetingContact] = [:]
    private var missingEmails: Set<String> = []

    private let contactKeysToFetch: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactNicknameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
    ]

    func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            contactStore.requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func resolve(organizer: MeetingOrganizer?) async -> MeetingOrganizer? {
        guard let organizer else { return nil }
        guard let emailAddress = normalizedEmailAddress(organizer.emailAddress) else { return organizer }
        guard let resolvedContact = await resolvedContact(for: emailAddress) else { return organizer }
        return organizer.applyingContact(
            displayText: resolvedContact.displayText,
            avatarImageData: resolvedContact.avatarImageData
        )
    }

    func resolve(attendees: [MeetingAttendee]) async -> [MeetingAttendee] {
        guard !attendees.isEmpty else { return [] }

        var resolvedAttendees: [MeetingAttendee] = []
        resolvedAttendees.reserveCapacity(attendees.count)

        for attendee in attendees {
            guard let emailAddress = normalizedEmailAddress(attendee.emailAddress),
                  let resolvedContact = await resolvedContact(for: emailAddress) else {
                resolvedAttendees.append(attendee)
                continue
            }

            resolvedAttendees.append(
                attendee.applyingContact(
                    displayText: resolvedContact.displayText,
                    avatarImageData: resolvedContact.avatarImageData
                )
            )
        }

        return resolvedAttendees
    }

    private func resolvedContact(for emailAddress: String) async -> ResolvedMeetingContact? {
        guard let normalizedEmailAddress = normalizedEmailAddress(emailAddress) else {
            return nil
        }

        if let cachedContact = cachedContactsByEmail[normalizedEmailAddress] {
            return cachedContact
        }

        if missingEmails.contains(normalizedEmailAddress) {
            return nil
        }

        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            return nil
        }

        do {
            let contacts = try contactStore.unifiedContacts(
                matching: CNContact.predicateForContacts(matchingEmailAddress: normalizedEmailAddress),
                keysToFetch: contactKeysToFetch
            )

            guard let bestMatch = contacts.first,
                  let displayText = Self.contactDisplayText(for: bestMatch, fallbackEmailAddress: normalizedEmailAddress) else {
                missingEmails.insert(normalizedEmailAddress)
                return nil
            }

            let resolvedContact = ResolvedMeetingContact(
                displayText: displayText,
                avatarImageData: bestMatch.thumbnailImageData
            )
            cachedContactsByEmail[normalizedEmailAddress] = resolvedContact
            return resolvedContact
        } catch {
            missingEmails.insert(normalizedEmailAddress)
            return nil
        }
    }

    private func normalizedEmailAddress(_ emailAddress: String?) -> String? {
        MeetingAttendee.normalizedEmailAddress(emailAddress)
    }

    private static func contactDisplayText(for contact: CNContact, fallbackEmailAddress: String) -> String? {
        if let fullName = CNContactFormatter.string(from: contact, style: .fullName)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fullName.isEmpty {
            return fullName
        }

        let nickname = contact.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nickname.isEmpty {
            return nickname
        }

        let organizationName = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !organizationName.isEmpty {
            return organizationName
        }

        return fallbackEmailAddress
    }
}
