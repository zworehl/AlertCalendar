import AppKit
import SwiftUI

struct FootballStatusAccessoriesData {
    let badgeText: String?
    let warningText: String?

    var hasAccessories: Bool {
        badgeText != nil || warningText != nil
    }

    static func resolved(for match: FootballFixtureMatch, now: Date = AlertCalendarClock.nowRoundedToSecond()) -> FootballStatusAccessoriesData {
        FootballStatusAccessoriesData(
            badgeText: CalendarMonitor.footballStatusBadgeText(for: match, now: now),
            warningText: CalendarMonitor.footballStatusWarningText(for: match)
        )
    }
}

struct FootballTeamLogoView: View {
    let localPath: String?
    let remoteURL: URL?
    let isUnknown: Bool
    var size: CGFloat = 16
    var placeholderSymbolSize: CGFloat = 8

    var body: some View {
        FootballRemoteLogoView(localPath: localPath, remoteURL: isUnknown ? nil : remoteURL, size: size) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
                .overlay(
                    Image(systemName: "shield")
                        .font(.system(size: placeholderSymbolSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                )
        }
    }
}

struct FootballCompetitionLogoView: View {
    let localPath: String?
    let remoteURL: URL?
    var size: CGFloat = 14
    var placeholderSymbolSize: CGFloat = 10

    var body: some View {
        FootballRemoteLogoView(localPath: localPath, remoteURL: remoteURL, size: size) {
            Image(systemName: "trophy")
                .font(.system(size: placeholderSymbolSize, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct FootballStatusBadgeView: View {
    let text: String

    var body: some View {
        let tint = Color(nsColor: CalendarMonitor.footballStatusTintColor(for: text))

        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.16))
            )
    }
}

struct FootballStatusWarningIconView: View {
    let helpText: String

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.orange)
            .help(helpText)
    }
}

struct FootballStatusAccessoriesView: View {
    let data: FootballStatusAccessoriesData

    init(match: FootballFixtureMatch, now: Date = AlertCalendarClock.nowRoundedToSecond()) {
        data = FootballStatusAccessoriesData.resolved(for: match, now: now)
    }

    init(data: FootballStatusAccessoriesData) {
        self.data = data
    }

    var body: some View {
        HStack(spacing: 6) {
            if let badgeText = data.badgeText {
                FootballStatusBadgeView(text: badgeText)
            }

            if let warningText = data.warningText {
                FootballStatusWarningIconView(helpText: warningText)
            }
        }
    }

    static func accessories(for match: FootballFixtureMatch, now: Date = AlertCalendarClock.nowRoundedToSecond()) -> FootballStatusAccessoriesData {
        .resolved(for: match, now: now)
    }

    static func hasAccessories(for match: FootballFixtureMatch, now: Date = AlertCalendarClock.nowRoundedToSecond()) -> Bool {
        accessories(for: match, now: now).hasAccessories
    }
}

private struct FootballRemoteLogoView<Placeholder: View>: View {
    let localPath: String?
    let remoteURL: URL?
    let size: CGFloat
    let placeholder: Placeholder
    @State private var localImage: NSImage?
    @State private var localImagePath: String?
    @State private var failedLocalImagePath: String?

    init(
        localPath: String?,
        remoteURL: URL?,
        size: CGFloat,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.localPath = localPath
        self.remoteURL = remoteURL
        self.size = size
        self.placeholder = placeholder()
    }

    var body: some View {
        let stateImage = localImagePath == localPath ? localImage : nil
        let cachedImage = localPath.flatMap { FootballLocalImageCache.cachedImage(for: $0) }
        let shouldLoadLocalImage = localPath != nil && failedLocalImagePath != localPath

        Group {
            if let image = stateImage ?? cachedImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else if shouldLoadLocalImage {
                placeholder
            } else {
                AsyncImage(url: remoteURL, transaction: Transaction(animation: nil)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                    } else {
                        placeholder
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .task(id: localPath) {
            await loadLocalImageIfNeeded()
        }
    }

    @MainActor
    private func loadLocalImageIfNeeded() async {
        guard let localPath else {
            localImage = nil
            localImagePath = nil
            failedLocalImagePath = nil
            return
        }

        if localImagePath == localPath, localImage != nil {
            return
        }

        if let cachedImage = FootballLocalImageCache.cachedImage(for: localPath) {
            localImage = cachedImage
            localImagePath = localPath
            failedLocalImagePath = nil
            return
        }

        localImage = nil
        localImagePath = localPath
        failedLocalImagePath = nil

        guard let image = await FootballLocalImageCache.loadImage(for: localPath),
              !Task.isCancelled,
              localImagePath == localPath else {
            if !Task.isCancelled, localImagePath == localPath {
                failedLocalImagePath = localPath
            }
            return
        }

        localImage = image
        failedLocalImagePath = nil
    }
}

@MainActor
enum FootballLocalImageCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 160
        return cache
    }()

    static func cachedImage(for path: String) -> NSImage? {
        cache.object(forKey: path as NSString)
    }

    static func store(_ image: NSImage, for path: String) {
        cache.setObject(image, forKey: path as NSString)
    }

    static func loadImage(for path: String) async -> NSImage? {
        if let cachedImage = cachedImage(for: path) {
            return cachedImage
        }

        guard let imageData = await imageData(for: path),
              !Task.isCancelled,
              let image = NSImage(data: imageData) else {
            return nil
        }

        store(image, for: path)
        return image
    }

    nonisolated static func imageData(for path: String) async -> Data? {
        await Task.detached(priority: .utility) {
            try? Data(contentsOf: URL(fileURLWithPath: path))
        }.value
    }
}
