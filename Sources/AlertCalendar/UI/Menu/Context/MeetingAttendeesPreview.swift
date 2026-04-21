import AppKit
import CoreLocation
import MapKit
import SwiftUI

struct MeetingAttendeesPreview: View {
    let organizer: MeetingOrganizer?
    let attendees: [MeetingAttendee]
    let listHeight: CGFloat

    @State private var presentedOrganizer: MeetingOrganizer?
    @State private var presentedAttendees: [MeetingAttendee] = []
    @State private var resolveTask: Task<Void, Never>?

    let columns = [
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12, alignment: .leading),
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12, alignment: .leading),
    ]

    var displayedOrganizer: MeetingOrganizer? {
        presentedOrganizer ?? organizer
    }

    var displayedAttendees: [MeetingAttendee] {
        presentedAttendees.isEmpty ? attendees : presentedAttendees
    }

    var resolverKey: String {
        let organizerKey = [
            organizer?.displayText ?? "",
            organizer?.emailAddress ?? "",
        ].joined(separator: "|")
        let attendeeKey = attendees
            .map { "\($0.id)|\($0.displayText)|\($0.emailAddress ?? "")|\($0.response.rawValue)" }
            .joined(separator: "|")
        return "\(organizerKey)#\(attendeeKey)"
    }

    var organizerSecondaryText: String? {
        guard let displayedOrganizer,
              let emailAddress = displayedOrganizer.emailAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
              !emailAddress.isEmpty,
              displayedOrganizer.displayText.localizedCaseInsensitiveCompare(emailAddress) != .orderedSame else {
            return nil
        }

        return emailAddress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let displayedOrganizer {
                HStack(alignment: .center, spacing: 10) {
                    MeetingOrganizerAvatar(organizer: displayedOrganizer)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Invitation from")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(displayedOrganizer.displayText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let organizerSecondaryText {
                            Text(organizerSecondaryText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: 0)
                }

                Divider()
                    .overlay(Color.primary.opacity(0.08))
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayedAttendees.count == 1 ? "Invitee" : "Invitees")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text("\(displayedAttendees.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ScrollView(.vertical, showsIndicators: displayedAttendees.count > 6) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(displayedAttendees) { attendee in
                        MeetingAttendeeRow(attendee: attendee)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(height: listHeight)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .onAppear {
            resolveContacts()
        }
        .onChange(of: resolverKey) { _ in
            resolveContacts()
        }
        .onDisappear {
            resolveTask?.cancel()
            resolveTask = nil
        }
    }

    func resolveContacts() {
        presentedOrganizer = organizer
        presentedAttendees = attendees
        resolveTask?.cancel()

        resolveTask = Task {
            let resolvedOrganizer = await MeetingContactResolver.shared.resolve(organizer: organizer)
            let resolvedAttendees = await MeetingContactResolver.shared.resolve(attendees: attendees)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                presentedOrganizer = resolvedOrganizer
                presentedAttendees = resolvedAttendees
            }
        }
    }
}

struct MeetingAttendeeRow: View {
    let attendee: MeetingAttendee

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: attendee.response.statusSymbolName)
                .font(.system(size: 14, weight: .regular))
                .frame(width: 14, height: 14, alignment: .center)
                .foregroundStyle(Color(nsColor: attendee.response.statusColor))

            Text(attendee.displayText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MeetingOrganizerAvatar: View {
    let organizer: MeetingOrganizer

    var body: some View {
        Group {
            if let avatarImageData = organizer.avatarImageData,
               let avatarImage = NSImage(data: avatarImageData) {
                Image(nsImage: avatarImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.39, green: 0.34, blue: 0.56),
                                    Color(red: 0.21, green: 0.17, blue: 0.37),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text(organizer.avatarFallbackText)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }
}
