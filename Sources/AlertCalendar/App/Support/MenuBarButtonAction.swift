import AppKit

/// One button press invokes one presentation-owner action. Mouse release does
/// not send another action after a dropdown has been dismissed.
@MainActor
final class MenuBarButtonAction: NSObject {
    private weak var button: NSStatusBarButton?
    private var onAction: (@MainActor () -> Void)?

    init(button: NSStatusBarButton, onAction: @escaping @MainActor () -> Void) {
        self.button = button
        self.onAction = onAction
        super.init()
        button.target = self
        button.action = #selector(performAction(_:))
        button.isContinuous = false
        button.sendAction(on: [.leftMouseDown])
    }

    func stop() {
        onAction = nil
        if let button, button.target === self {
            button.target = nil
            button.action = nil
        }
        button = nil
    }

    @objc private func performAction(_ sender: Any?) {
        onAction?()
    }
}
