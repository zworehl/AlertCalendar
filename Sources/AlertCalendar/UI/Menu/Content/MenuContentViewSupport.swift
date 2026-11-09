import AppKit
import CoreLocation
import MapKit
import SwiftUI

struct SplitUpcomingPanelHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SplitRightColumnHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SplitContextualPanelMeasurement: Equatable {
    let key: String
    let height: CGFloat
}

struct SplitContextualPanelMeasurementPreferenceKey: PreferenceKey {
    static let defaultValue = SplitContextualPanelMeasurement(key: "", height: 0)

    static func reduce(
        value: inout SplitContextualPanelMeasurement,
        nextValue: () -> SplitContextualPanelMeasurement
    ) {
        let nextMeasurement = nextValue()
        if nextMeasurement.height > value.height {
            value = nextMeasurement
        }
    }
}

struct MapMarkerItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
