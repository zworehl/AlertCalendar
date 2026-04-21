import AppKit
import SwiftUI

struct FootballStatusAccessoriesData {
    let badgeText: String?
    let warningText: String?

    var hasAccessories: Bool {
        badgeText != nil || warningText != nil
    }

    static func resolved(for match: FootballFixtureMatch, now: Date = Date()) -> FootballStatusAccessoriesData {
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

    init(match: FootballFixtureMatch, now: Date = Date()) {
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

    static func accessories(for match: FootballFixtureMatch, now: Date = Date()) -> FootballStatusAccessoriesData {
        .resolved(for: match, now: now)
    }

    static func hasAccessories(for match: FootballFixtureMatch, now: Date = Date()) -> Bool {
        accessories(for: match, now: now).hasAccessories
    }
}

private struct FootballRemoteLogoView<Placeholder: View>: View {
    let localPath: String?
    let remoteURL: URL?
    let size: CGFloat
    let placeholder: Placeholder

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
        if let localPath,
           let image = FootballLocalImageCache.image(for: localPath) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
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
            .frame(width: size, height: size)
        }
    }
}

@MainActor
private enum FootballLocalImageCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        return cache
    }()

    static func image(for path: String) -> NSImage? {
        let key = path as NSString
        if let cachedImage = cache.object(forKey: key) {
            return cachedImage
        }

        guard let image = NSImage(contentsOfFile: path) else {
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }
}
