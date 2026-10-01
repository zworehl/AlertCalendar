import Contacts
import Foundation

struct ResolvedMeetingContact: Equatable, Sendable {
    let displayText: String?
    let avatarImageData: Data?
}

extension Notification.Name {
    static let alertCalendarMeetingContactsDidChange = Notification.Name("AlertCalendarMeetingContactsDidChange")
}

actor MeetingContactResolver {
    static let shared = MeetingContactResolver()

    private let contactStore: any MeetingContactStoreProviding
    private let notificationCenter: NotificationCenter
    private var contactChangesTask: Task<Void, Never>?
    private var cachedContactsByEmail: [String: ResolvedMeetingContact] = [:]
    private var missingEmails: Set<String> = []
    private var cachedAuthorizationStatus: CNAuthorizationStatus?
    private var cacheGeneration = 0

    init(
        contactStore: any MeetingContactStoreProviding = SystemMeetingContactStore(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.contactStore = contactStore
        self.notificationCenter = notificationCenter
    }

    deinit {
        contactChangesTask?.cancel()
    }

    func requestAccess() async -> Bool {
        let status = await contactStore.authorizationStatus()
        if Self.canReadContacts(status) {
            return true
        }
        guard status == .notDetermined else {
            return false
        }

        let granted = await contactStore.requestAccess()
        invalidateCache()
        return granted
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

        return MeetingAttendee.normalized(resolvedAttendees)
    }

    private func resolvedContact(for emailAddress: String) async -> ResolvedMeetingContact? {
        guard let normalizedEmailAddress = normalizedEmailAddress(emailAddress) else {
            return nil
        }

        startObservingContactChangesIfNeeded()
        let status = await contactStore.authorizationStatus()
        if status != cachedAuthorizationStatus {
            invalidateCache()
            cachedAuthorizationStatus = status
        }
        guard Self.canReadContacts(status) else { return nil }

        if let cachedContact = cachedContactsByEmail[normalizedEmailAddress] {
            return cachedContact
        }

        if missingEmails.contains(normalizedEmailAddress) {
            return nil
        }

        let generation = cacheGeneration
        do {
            let resolvedContact = try await contactStore.contact(matchingEmailAddress: normalizedEmailAddress)
            guard generation == cacheGeneration, !Task.isCancelled else { return nil }
            guard let resolvedContact else {
                missingEmails.insert(normalizedEmailAddress)
                return nil
            }

            cachedContactsByEmail[normalizedEmailAddress] = resolvedContact
            return resolvedContact
        } catch {
            // A temporary Contacts failure must not hide a photo for the rest of the session.
            return nil
        }
    }

    func invalidateCache() {
        cachedContactsByEmail.removeAll()
        missingEmails.removeAll()
        cacheGeneration += 1
    }

    private func startObservingContactChangesIfNeeded() {
        guard contactChangesTask == nil else { return }
        let changes = notificationCenter.notifications(named: .CNContactStoreDidChange)
            .map { _ in () }
        contactChangesTask = Task { [weak self] in
            for await _ in changes {
                guard !Task.isCancelled else { return }
                await self?.contactStoreDidChange()
            }
        }
    }

    private func contactStoreDidChange() async {
        invalidateCache()
        let notificationCenter = notificationCenter
        await MainActor.run {
            notificationCenter.post(name: .alertCalendarMeetingContactsDidChange, object: nil)
        }
    }

    private static func canReadContacts(_ status: CNAuthorizationStatus) -> Bool {
        status == .authorized
    }

    private func normalizedEmailAddress(_ emailAddress: String?) -> String? {
        MeetingAttendee.normalizedEmailAddress(emailAddress)
    }
}
