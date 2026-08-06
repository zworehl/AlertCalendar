import AppKit
import SwiftUI

enum GameStoreSymbolProvider {
    @MainActor
    static func image(for store: GameStore, size: CGFloat) -> NSImage? {
        let resolvedSize = max(8, size)
        guard let assetURL = assetURL(for: store),
              let sourceImage = NSImage(contentsOf: assetURL) else {
            return nil
        }

        let image = NSImage(size: NSSize(width: resolvedSize, height: resolvedSize))
        image.lockFocus()
        defer { image.unlockFocus() }

        let bounds = NSRect(x: 0, y: 0, width: resolvedSize, height: resolvedSize)
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        NSGraphicsContext.current?.imageInterpolation = .high
        sourceImage.draw(in: aspectFitRect(for: sourceImage.size, in: bounds))
        brandColor(for: store).setFill()
        bounds.fill(using: .sourceAtop)

        image.isTemplate = false
        return image
    }

    static func assetURL(for store: GameStore) -> URL? {
        let assetName: String
        switch store {
        case .steam:
            assetName = "game-store-steam"
        case .xbox:
            assetName = "game-store-xbox"
        case .playStation:
            assetName = "game-store-playstation"
        case .nintendoSwitch:
            assetName = "game-store-nintendo-switch"
        }

        return Bundle.module.url(forResource: assetName, withExtension: "svg")
            ?? Bundle.module.url(
                forResource: assetName,
                withExtension: "svg",
                subdirectory: "Resources/Images"
            )
    }

    static func brandColor(for store: GameStore) -> NSColor {
        switch store {
        case .steam:
            return NSColor(srgbRed: 0.40, green: 0.75, blue: 0.96, alpha: 1)
        case .xbox:
            return NSColor(srgbRed: 0.06, green: 0.57, blue: 0.07, alpha: 1)
        case .playStation:
            return NSColor(srgbRed: 0.00, green: 0.44, blue: 0.80, alpha: 1)
        case .nintendoSwitch:
            return NSColor(srgbRed: 0.90, green: 0.00, blue: 0.07, alpha: 1)
        }
    }

    private static func aspectFitRect(for imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

struct GameStoreIconView: View {
    let store: GameStore
    let size: CGFloat

    var body: some View {
        Group {
            if let image = GameStoreSymbolProvider.image(for: store, size: size) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: store.systemImageName)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(Color(nsColor: GameStoreSymbolProvider.brandColor(for: store)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(store.title)
    }
}
