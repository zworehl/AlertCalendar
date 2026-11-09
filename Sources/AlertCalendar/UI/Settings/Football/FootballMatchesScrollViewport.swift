import SwiftUI

private struct FootballMatchesContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct FootballMatchesScrollViewport<Content: View>: View {
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat
    let fillsAvailableHeight: Bool
    let content: Content

    @State private var measuredContentHeight: CGFloat = 0

    init(
        minimumHeight: CGFloat,
        maximumHeight: CGFloat,
        fillsAvailableHeight: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.minimumHeight = minimumHeight
        self.maximumHeight = maximumHeight
        self.fillsAvailableHeight = fillsAvailableHeight
        self.content = content()
    }

    private var viewportHeight: CGFloat {
        min(max(measuredContentHeight, minimumHeight), maximumHeight)
    }

    private var contentNeedsScrolling: Bool {
        measuredContentHeight > maximumHeight + 1
    }

    private var showsScrollIndicators: Bool {
        fillsAvailableHeight || contentNeedsScrolling
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: showsScrollIndicators) {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: FootballMatchesContentHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                )
        }
        .scrollDisabled(!fillsAvailableHeight && !contentNeedsScrolling)
        .frame(
            minHeight: minimumHeight,
            idealHeight: viewportHeight,
            maxHeight: fillsAvailableHeight ? .infinity : viewportHeight,
            alignment: .top
        )
        .clipped()
        .onPreferenceChange(FootballMatchesContentHeightPreferenceKey.self) { height in
            measuredContentHeight = height
        }
    }
}
