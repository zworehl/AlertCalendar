import AppKit
import SwiftUI

struct MenuActionButton: NSViewRepresentable {
    let systemImage: String
    let toolTip: String
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> MenuActionNSButton {
        let button = MenuActionNSButton(frame: .zero)
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: MenuActionNSButton, context: Context) {
        button.configure(
            systemImage: systemImage,
            toolTip: toolTip,
            accessibilityLabel: accessibilityLabel,
            isEnabled: isEnabled,
            action: action
        )
    }
}

final class MenuActionNSButton: NSButton {
    private var systemImageName: String?
    private var onAction: (() -> Void)?

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: MenuActionControlMetrics.minimumHitTargetSize,
            height: MenuActionControlMetrics.minimumHitTargetSize
        )
    }

    override var alignmentRectInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.momentaryPushIn)
        bezelStyle = .rounded
        controlSize = .small
        title = ""
        target = self
        action = #selector(invokeAction)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        systemImage: String,
        toolTip: String,
        accessibilityLabel: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) {
        if systemImageName != systemImage {
            systemImageName = systemImage
            image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: MenuActionControlMetrics.symbolSize, weight: .medium))
            imagePosition = .imageOnly
        }
        // Keep AppKit's tooltip tracking intact across countdown and hover updates.
        if self.toolTip != toolTip {
            self.toolTip = toolTip
        }
        setAccessibilityLabel(accessibilityLabel)
        self.isEnabled = isEnabled
        onAction = action
    }

    @objc private func invokeAction() {
        guard isEnabled else { return }
        onAction?()
    }
}
