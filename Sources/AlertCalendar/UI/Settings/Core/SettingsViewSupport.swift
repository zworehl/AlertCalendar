import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

enum PermissionGrantState: String, CaseIterable {
    case allowed
    case notRequested
    case limited
    case denied
    case restricted

    var badgeTitle: String {
        switch self {
        case .allowed:
            return "Allowed"
        case .notRequested:
            return "Not Requested"
        case .limited:
            return "Limited"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        }
    }

    var tint: Color {
        switch self {
        case .allowed:
            return Color(red: 0.24, green: 0.72, blue: 0.33)
        case .notRequested:
            return Color(red: 0.24, green: 0.59, blue: 0.97)
        case .limited:
            return Color(red: 1.0, green: 0.62, blue: 0.21)
        case .denied:
            return Color(red: 0.92, green: 0.31, blue: 0.28)
        case .restricted:
            return Color.secondary
        }
    }
}

struct SettingsPermissionIconView: View {
    let fallbackSymbolName: String
    let gradient: LinearGradient
    let appIconPath: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60 * 60)) { _ in
            ZStack {
                if let image = Self.appIconImage(for: appIconPath) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(gradient.opacity(0.18))

                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)

                    Image(systemName: fallbackSymbolName)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 56, height: 56)
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    static func appIconImage(for appPath: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: appPath) else { return nil }
        return AlertCalendarWorkspace.icon(forFile: appPath, size: NSSize(width: 64, height: 64))
    }
}

struct SettingsViewportHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SettingsWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void
    let onResize: (CGFloat) -> Void

    func makeNSView(context: Context) -> SettingsWindowObserverView {
        SettingsWindowObserverView(onResolve: onResolve, onResize: onResize)
    }

    func updateNSView(_ nsView: SettingsWindowObserverView, context: Context) {
        nsView.onResolve = onResolve
        nsView.onResize = onResize
        nsView.resolveWindowIfNeeded()
    }
}

final class SettingsWindowObserverView: NSView {
    var onResolve: (NSWindow) -> Void
    var onResize: (CGFloat) -> Void
    weak var lastResolvedWindow: NSWindow?
    weak var observedWindow: NSWindow?

    init(onResolve: @escaping (NSWindow) -> Void, onResize: @escaping (CGFloat) -> Void) {
        self.onResolve = onResolve
        self.onResize = onResize
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        lastResolvedWindow = nil
        resolveWindowIfNeeded(force: true)
    }

    func resolveWindowIfNeeded(force: Bool = false) {
        guard let window else { return }
        guard force || lastResolvedWindow !== window else { return }
        lastResolvedWindow = window
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.onResolve(window)
            self.startObservingResize(for: window)
        }
    }

    func startObservingResize(for window: NSWindow) {
        guard observedWindow !== window else { return }
        stopObservingResize()
        observedWindow = window
        onResize(window.frame.width)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowResize),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }

    func stopObservingResize() {
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: observedWindow)
        observedWindow = nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleWindowResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        onResize(window.frame.width)
    }
}

extension SettingsView {
    var settingsUsesTwoColumnLayout: Bool {
        settingsWindowWidth >= 1120
    }

    var settingsUsesPreviewColumnLayout: Bool {
        settingsWindowWidth >= 1240
    }

    var settingsControlColumnWidth: CGFloat {
        let availableWidth = max(settingsWindowWidth - 40, 0)
        return min(max(availableWidth * 0.34, 340), 460)
    }

    @ViewBuilder
    func settingsSection<Content: View>(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SettingsVisualMetrics.sectionContentSpacing) {
            settingsSectionHeader(title: title, subtitle: subtitle, systemImage: systemImage)
            content()
        }
        .padding(SettingsVisualMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(SettingsPanelChrome())
    }

    @ViewBuilder
    func settingsSectionHeader(title: String, subtitle: String? = nil, systemImage: String? = nil) -> some View {
        SettingsSectionHeaderView(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage
        )
    }

    @ViewBuilder
    func settingsControlRow<Control: View>(
        title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                settingsControlCopy(title: title, detail: detail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                control()
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 8) {
                settingsControlCopy(title: title, detail: detail)
                control()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    func settingsControlCopy(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(SettingsTypography.controlTitle)
                .foregroundStyle(.primary)

            Text(detail)
                .font(SettingsTypography.supportingText)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    func settingsDivider() -> some View {
        Divider()
            .overlay(Color.primary.opacity(0.04))
    }
}
