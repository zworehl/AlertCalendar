import AppKit
import CoreLocation
import MapKit
import SwiftUI

struct MiniLocationMapView: View {
    let locationText: String
    let preferredHeight: CGFloat

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 18.4655, longitude: -66.1057),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
    @State private var marker: MapMarkerItem?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Location Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack {
                if let marker {
                    Map(
                        coordinateRegion: $region,
                        annotationItems: [marker]
                    ) { item in
                        MapMarker(coordinate: item.coordinate, tint: .red)
                    }
                    .allowsHitTesting(false)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                    Text(isLoading ? "Loading map..." : "Map unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: preferredHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onAppear {
            resolveLocation()
        }
        .onChange(of: locationText) { _ in
            resolveLocation()
        }
    }

    private func resolveLocation() {
        let requestedLocation = locationText
        let trimmed = requestedLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            isLoading = false
            marker = nil
            return
        }

        isLoading = true
        Task {
            let coordinate = await LocationCoordinateResolver.shared.coordinate(for: requestedLocation)
            await MainActor.run {
                guard requestedLocation == locationText else { return }
                isLoading = false
                guard let coordinate else {
                    marker = nil
                    return
                }
                setMarker(at: coordinate.clCoordinate)
            }
        }
    }

    private func setMarker(at coordinate: CLLocationCoordinate2D) {
        marker = MapMarkerItem(coordinate: coordinate)
        region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    }
}
