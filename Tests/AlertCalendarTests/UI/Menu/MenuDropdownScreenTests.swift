import AppKit
import SwiftUI
import XCTest
@testable import AlertCalendar

@MainActor
final class MenuDropdownScreenTests: XCTestCase {
    private let laptop = MenuDropdownScreen(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 40, width: 1512, height: 904),
        backingScaleFactor: 2
    )
    private let external = MenuDropdownScreen(
        id: 2,
        frame: CGRect(x: -900, y: 982, width: 3840, height: 1620),
        visibleFrame: CGRect(x: -900, y: 982, width: 3840, height: 1596),
        backingScaleFactor: 1
    )

    func testBothDisplaysShareOneLayoutThatFitsTheLaptop() {
        let size = MenuDropdownScreen.commonAvailableSize(screens: [laptop, external])
        XCTAssertEqual(size, MenuDropdownScreen.commonAvailableSize(screens: [external, laptop]))
        XCTAssertEqual(size, MenuDropdownScreen.commonAvailableSize(screens: [laptop]))
        XCTAssertEqual(size, MenuDropdownScreen.commonAvailableSize(screens: [external]),
                       "Unplugging the laptop must not grow the dropdown on the external display")
        XCTAssertEqual(size, CGSize(width: 708, height: 800))
        for screen in [laptop, external] {
            XCTAssertLessThan(size.width, screen.visibleFrame.width)
            XCTAssertLessThan(size.height, screen.visibleFrame.height)
        }
    }

    func testChangingScaleAndScreenArrangementDoesNotChangeMenuLayout() {
        let rearranged = MenuDropdownScreen(
            id: external.id,
            frame: CGRect(x: -3840, y: -400, width: 3840, height: 1620),
            visibleFrame: CGRect(x: -3840, y: -400, width: 3840, height: 1596),
            backingScaleFactor: 2
        )
        XCTAssertEqual(
            MenuDropdownScreen.commonAvailableSize(screens: [laptop, external]),
            MenuDropdownScreen.commonAvailableSize(screens: [laptop, rearranged])
        )
    }

    func testLargeVerticalGapIsReanchoredWithoutChangingHorizontalPosition() {
        let window = CGRect(x: 48, y: 120, width: 708, height: 590)
        let visible = CGRect(x: 0, y: 40, width: 1512, height: 904)

        XCTAssertEqual(
            MenuDropdownScreen.correctedDropdownOrigin(windowFrame: window, visibleFrame: visible),
            CGPoint(x: 48, y: 350)
        )
    }

    func testDropdownScreenIsResolvedFromPanelIntersection() {
        let panelOnLaptop = CGRect(x: 48, y: 120, width: 708, height: 590)
        let panelOnExternal = CGRect(x: 2100, y: 1200, width: 708, height: 590)

        XCTAssertEqual(
            MenuDropdownScreen.visibleFrameForDropdown(
                windowFrame: panelOnLaptop,
                screens: [external, laptop]
            ),
            laptop.visibleFrame
        )
        XCTAssertEqual(
            MenuDropdownScreen.visibleFrameForDropdown(
                windowFrame: panelOnExternal,
                screens: [laptop, external]
            ),
            external.visibleFrame
        )
    }

    func testDropdownScreenFallsBackToNearestDisplayWhenPanelIsBetweenScreens() {
        let panel = CGRect(x: 1600, y: 200, width: 100, height: 100)

        XCTAssertEqual(
            MenuDropdownScreen.visibleFrameForDropdown(
                windowFrame: panel,
                screens: [external, laptop]
            ),
            laptop.visibleFrame
        )
    }

    func testNormalNativeMenuGapIsPreserved() {
        let visible = CGRect(x: 0, y: 40, width: 1512, height: 904)
        let normallyAnchored = CGRect(x: 48, y: 346, width: 708, height: 590)

        XCTAssertNil(
            MenuDropdownScreen.correctedDropdownOrigin(
                windowFrame: normallyAnchored,
                visibleFrame: visible
            )
        )
    }

    func testShortScreenLimitsViewportWithoutUsingPixelsOrNegativeOrigins() {
        let short = MenuDropdownScreen(
            id: 3, frame: CGRect(x: -1024, y: -600, width: 1024, height: 600),
            visibleFrame: CGRect(x: -1024, y: -560, width: 1024, height: 536),
            backingScaleFactor: 2
        )
        XCTAssertEqual(MenuDropdownScreen.commonAvailableSize(screens: [laptop, short]),
                       CGSize(width: 708, height: 520))
        XCTAssertEqual(MenuDropdownScreen.commonAvailableSize(screens: []),
                       CGSize(width: 708, height: 800))
    }

    func testMenuHeightDoesNotCollapseOrExpandDuringNativeSizeProposals() {
        let host = NSHostingController(rootView: VStack(spacing: 0) {
            Text("Alert Calendar").frame(height: 43)
            MenuDropdownHeightContainer(maximumHeight: 597) {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        ScrollView { Color.red.frame(height: 1200) }.frame(width: 336, height: 428)
                        ScrollView { Color.blue.frame(height: 1200) }.frame(width: 336, height: 428)
                    }
                    Text("Agenda Summary").frame(height: 84)
                }.padding(12)
            }
        }.fixedSize(horizontal: false, vertical: true).frame(width: 708))
        settleLayout(host.view, size: CGSize(width: 708, height: 640))

        // MenuBarExtra probes minimum, ideal, and maximum sizes. Previously the
        // same content reported 43, 360, and 888 points depending on the proposal.
        let expected = host.sizeThatFits(in: CGSize(width: 708, height: 640))
        XCTAssertEqual(expected.height, 587, accuracy: 1)
        for proposedHeight: CGFloat in [0, 100, 360, 600, 982, 1620, 10_000] {
            let size = host.sizeThatFits(in: CGSize(width: 708, height: proposedHeight))
            XCTAssertEqual(size.width, 708, accuracy: 1)
            XCTAssertEqual(size.height, expected.height, accuracy: 1)
        }
    }

    func testOneContentTreeKeepsShortMenusCompactAndTallMenusScrollable() {
        for (contentHeight, expectedHeight): (CGFloat, CGFloat) in [(180, 180), (1200, 420)] {
            var measuredContentHeight: CGFloat = 0
            let host = NSHostingController(rootView: MenuDropdownHeightContainer(maximumHeight: 420) {
                Color.clear.frame(width: 360, height: contentHeight)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: TestContentHeightKey.self, value: proxy.size.height)
                        }
                    }
            }.frame(width: 360).onPreferenceChange(TestContentHeightKey.self) {
                measuredContentHeight = $0
            })
            settleLayout(host.view, size: CGSize(width: 360, height: 420))
            XCTAssertEqual(host.sizeThatFits(in: CGSize(width: 360, height: 0)).height,
                           expectedHeight, accuracy: 1)
            let scrollViews = descendants(of: host.view).compactMap { $0 as? NSScrollView }
            XCTAssertEqual(scrollViews.count, contentHeight > 420 ? 1 : 0,
                           "Content that fits must not create a scroll view")
            XCTAssertEqual(measuredContentHeight, contentHeight, accuracy: 1,
                           "Long content must retain its natural height inside the bounded scroll view")
        }
    }

    func testInitialHeightProbeDoesNotClaimTheMaximumBeforeContentIsMeasured() {
        let host = NSHostingController(rootView: MenuDropdownHeightContainer(maximumHeight: 420) {
            Color.clear.frame(width: 360, height: 180)
        }.frame(width: 360))

        let initialSize = host.sizeThatFits(in: CGSize(width: 360, height: 420))

        XCTAssertLessThan(
            initialSize.height,
            100,
            "The initial MenuBarExtra probe must stay compact so its top edge remains anchored"
        )
    }

    func testNestedColumnOverflowDoesNotAddAnOuterScrollView() {
        for contentHeight: CGFloat in [180, 1200] {
            let host = NSHostingController(rootView: MenuDropdownHeightContainer(maximumHeight: 757) {
                VStack(spacing: 8) {
                    MenuDropdownHeightContainer(maximumHeight: 600) {
                        Color.clear.frame(width: 360, height: contentHeight)
                    }
                    Text("Agenda Summary").frame(height: 84)
                }
            }.frame(width: 360))
            settleLayout(host.view, size: CGSize(width: 360, height: 757))
            XCTAssertEqual(host.sizeThatFits(in: CGSize(width: 360, height: 0)).height,
                           min(contentHeight, 600) + 92, accuracy: 1)
            XCTAssertEqual(descendants(of: host.view).compactMap { $0 as? NSScrollView }.count,
                           contentHeight > 600 ? 1 : 0,
                           "Only the overflowing column should scroll")
        }
    }

    func testHeightShrinksAndGrowsWithLiveContentWithinTheSameMaximum() {
        func content(height: CGFloat) -> some View {
            VStack(spacing: 0) {
                Text("Alert Calendar").frame(height: 43)
                MenuDropdownHeightContainer(maximumHeight: 757) {
                    Color.clear.frame(width: 360, height: height)
                }
            }.frame(width: 360).fixedSize(horizontal: false, vertical: true)
        }
        let host = NSHostingController(rootView: content(height: 900))
        for (height, expected): (CGFloat, CGFloat) in [(900, 800), (180, 223), (1200, 800), (240, 283)] {
            host.rootView = content(height: height)
            settleLayout(host.view, size: CGSize(width: 360, height: 800))
            XCTAssertEqual(host.sizeThatFits(in: CGSize(width: 360, height: 982)).height,
                           expected, accuracy: 1)
            XCTAssertEqual(host.sizeThatFits(in: CGSize(width: 360, height: 1620)).height,
                           expected, accuracy: 1)
        }
    }

    func testDisplayNotificationsRefreshConstraintsWithoutMovingOrResizingNativeWindow() {
        let window = NSWindow(
            contentRect: CGRect(x: 780, y: 220, width: 708, height: 590),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        let originalFrame = window.frame
        let observer = MenuDropdownWindowObserverView()
        var screens = [laptop, external]
        observer.connectedScreens = { screens }
        var published: CGSize?
        observer.presentationDidChange = { _, size in published = size }
        window.contentView = observer
        observer.updatePresentation()
        XCTAssertEqual(published, CGSize(width: 708, height: 800))
        XCTAssertEqual(window.frame, originalFrame)

        screens = [external]
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        XCTAssertEqual(published, CGSize(width: 708, height: 800))
        XCTAssertEqual(window.frame, originalFrame)

        observer.stopObserving()
        published = nil
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        XCTAssertNil(published)
    }

    private func settleLayout(_ view: NSView, size: CGSize) {
        view.frame = CGRect(origin: .zero, size: size)
        for _ in 0..<4 {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

private struct TestContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
