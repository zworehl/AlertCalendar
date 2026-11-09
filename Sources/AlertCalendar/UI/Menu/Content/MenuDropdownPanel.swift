import AppKit
import SwiftUI

/// A key-capable panel can accept keyboard navigation without activating the
/// app, changing its menu bar, or bringing a Settings window to the front.
@MainActor
final class MenuDropdownPanel: NSPanel {
    var onDismiss: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        level = .popUpMenu
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        autorecalculatesKeyViewLoop = true
        identifier = NSUserInterfaceItemIdentifier("menu-dropdown")
        MenuDropdownAppearance.configure(self)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}

@MainActor
final class MenuDropdownHostingView: NSHostingView<AnyView> {
    var onSizeChange: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onSizeChange?()
    }
}
