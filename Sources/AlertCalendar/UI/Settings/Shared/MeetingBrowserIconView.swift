import AppKit
import SwiftUI

struct MeetingBrowserIconView: View {
    let browser: MeetingBrowserKind

    var body: some View {
        if let icon = Self.icon(for: browser) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: fallbackSymbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var fallbackSymbolName: String {
        switch browser {
        case .chrome, .edge, .brave, .vivaldi, .chromium, .arc, .opera, .duckDuckGo, .orion:
            return "circle.hexagongrid.circle"
        case .safari:
            return "safari"
        case .firefox, .firefoxDeveloperEdition, .librewolf, .floorp, .zen:
            return "flame"
        }
    }

    private static func icon(for browser: MeetingBrowserKind) -> NSImage? {
        guard let appURL = MeetingBrowserCatalog.applicationURL(for: browser) else { return nil }
        return AlertCalendarWorkspace.icon(forFile: appURL.path, size: NSSize(width: 32, height: 32))
    }
}
