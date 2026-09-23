import SwiftUI

/// Give MenuBarExtra a finite ideal AND minimum height. ViewThatFits with a
/// ScrollView alternative accepts every proposed height, including zero during
/// native window measurement. Start with a small nonzero viewport, then grow to
/// the measured content height so AppKit keeps the panel's top edge anchored.
struct MenuDropdownHeightContainer<Content: View>: View {
    let maximumHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0
    @State private var measurementID = UUID()

    private var viewportHeight: CGFloat {
        min(maximumHeight, contentHeight > 0 ? contentHeight : 1)
    }

    var body: some View {
        Group {
            if contentHeight > maximumHeight + 0.5 {
                ScrollView(.vertical) {
                    measuredContent
                }
            } else {
                measuredContent
            }
        }
        .frame(height: viewportHeight, alignment: .top)
        .clipped()
        .onPreferenceChange(MenuDropdownBodyHeightKey.self) { heights in
            guard let height = heights[measurementID], height > 0, abs(contentHeight - height) > 0.5 else { return }
            contentHeight = ceil(height)
        }
    }

    private var measuredContent: some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: MenuDropdownBodyHeightKey.self, value: [measurementID: proxy.size.height])
                }
            }
    }
}

private struct MenuDropdownBodyHeightKey: PreferenceKey {
    static let defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
