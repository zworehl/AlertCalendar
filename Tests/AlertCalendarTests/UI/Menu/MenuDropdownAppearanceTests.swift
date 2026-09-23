import AppKit
import SwiftUI
import XCTest
@testable import AlertCalendar

@MainActor
final class MenuDropdownAppearanceTests: XCTestCase {
    func testDropdownWindowHasNoOpaqueBackdropOrNativeShadow() {
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 708, height: 587),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isOpaque = true
        window.hasShadow = true
        window.backgroundColor = .red
        let frame = window.frame

        MenuDropdownAppearance.configure(window)

        XCTAssertFalse(window.isOpaque)
        XCTAssertFalse(window.hasShadow)
        XCTAssertEqual(window.backgroundColor.alphaComponent, 0)
        XCTAssertEqual(window.frame, frame)
    }

    func testChangingDisplayOrScaleClearsRecreatedWindowShadow() {
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 708, height: 587),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        let observer = MenuDropdownWindowObserverView()
        window.contentView = observer
        for name in [NSWindow.didBecomeKeyNotification,
                     NSWindow.didChangeBackingPropertiesNotification,
                     NSWindow.didChangeScreenNotification,
                     NSWindow.didResizeNotification,
                     NSApplication.didChangeScreenParametersNotification] {
            window.hasShadow = true
            window.isOpaque = true
            window.backgroundColor = .red
            NotificationCenter.default.post(name: name, object: window)
            XCTAssertFalse(window.hasShadow, "\(name) must clear the window shadow")
            XCTAssertFalse(window.isOpaque)
            XCTAssertEqual(window.backgroundColor.alphaComponent, 0)
        }
        observer.stopObserving()
    }

    func testSurfaceHasTheSameRoundedOpaqueAppearanceAtBothDisplayScales() throws {
        for scheme in [ColorScheme.light, .dark] {
            var referenceColor: NSColor?
            for scale: CGFloat in [1, 2] {
                let renderer = ImageRenderer(content:
                    Color.clear.frame(width: 708, height: 587)
                        .modifier(MenuDropdownSurface())
                        .environment(\.colorScheme, scheme)
                )
                renderer.scale = scale
                let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
                XCTAssertEqual(bitmap.pixelsWide, Int(708 * scale))
                XCTAssertEqual(bitmap.pixelsHigh, Int(587 * scale))
                for (x, y) in [(0, 0), (bitmap.pixelsWide - 1, 0),
                               (0, bitmap.pixelsHigh - 1),
                               (bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1)] {
                    XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0,
                                   accuracy: 0.001, "Corners must not contain a rectangular material")
                }
                let fill = try XCTUnwrap(bitmap.colorAt(x: Int(354 * scale), y: Int(293 * scale))?.usingColorSpace(.deviceRGB))
                XCTAssertEqual(fill.alphaComponent, 1, accuracy: 0.001,
                               "The wallpaper must not change the menu's surface between displays")
                if let referenceColor {
                    XCTAssertEqual(fill.redComponent, referenceColor.redComponent, accuracy: 0.005)
                    XCTAssertEqual(fill.greenComponent, referenceColor.greenComponent, accuracy: 0.005)
                    XCTAssertEqual(fill.blueComponent, referenceColor.blueComponent, accuracy: 0.005)
                }
                referenceColor = fill
            }
        }
    }
}
