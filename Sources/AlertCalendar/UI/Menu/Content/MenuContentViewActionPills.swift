import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Spacer()
        }
    }

    func emptySectionRow(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    func timeRangeText(for item: UpcomingItem) -> String? {
        guard !item.isAllDay else { return nil }
        let startText = Self.menuTimeFormatter.string(from: item.date)
        guard let endDate = item.endDate, endDate > item.date else {
            return startText
        }
        let endText = Self.menuTimeFormatter.string(from: endDate)
        return "\(startText)-\(endText)"
    }

    @ViewBuilder
    func actionPill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(height: 18)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                    )
            )
    }

    @ViewBuilder
    func joinActionButton(for meetingURL: URL) -> some View {
        Button {
            NSWorkspace.shared.open(meetingURL)
        } label: {
            actionPill {
                Text("Join")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Join")
    }

    @ViewBuilder
    func skipActionButton(for item: UpcomingItem) -> some View {
        Button {
            monitor.skipItem(item)
        } label: {
            actionPill {
                Text("Skip")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Skip")
    }

    @ViewBuilder
    func mapActionButton(for item: UpcomingItem, locationText: String) -> some View {
        Button {
            openMap(for: item, locationText: locationText)
        } label: {
            actionPill {
                HStack(spacing: 4) {
                    Image(systemName: "map")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Map")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Map")
    }

    func reminderCompletionActionLabel(color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .fill(Color.primary.opacity(0.08))

            Circle()
                .stroke(color.opacity(0.96), lineWidth: 1.8)
                .padding(1.2)

            Circle()
                .fill(color.opacity(0.98))
                .padding(4.9)
        }
        .frame(width: 18, height: 18)
    }

    static let menuTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    nonisolated static func measuredTextWidth(_ text: String, font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    func timeText(_ date: Date) -> String {
        Self.menuTimeFormatter.string(from: date)
    }

    func eventTravelStartDate(for item: UpcomingItem) -> Date? {
        guard let travelMinutes = item.travelTimeMinutes, travelMinutes > 0 else { return nil }
        return item.date.addingTimeInterval(TimeInterval(-travelMinutes * 60))
    }

    func displayLocationName(from rawLocation: String) -> String {
        let trimmed = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return rawLocation }

        let primary = trimmed
            .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? trimmed

        return primary.isEmpty ? trimmed : primary
    }

    func shouldShowLocationRow(locationName: String, meetingURL: URL?) -> Bool {
        let normalizedLocation = locationName.lowercased()
        guard !normalizedLocation.isEmpty else { return false }

        if monitor.isVirtualLocationText(locationName) {
            return false
        }

        guard let meetingURL else { return true }

        if normalizedLocation.contains("microsoft teams"),
           meetingServiceName(for: meetingURL) == "Microsoft Teams" {
            return false
        }

        return true
    }
}
