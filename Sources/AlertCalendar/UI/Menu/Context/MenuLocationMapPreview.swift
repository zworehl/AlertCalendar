import AppKit
import CoreLocation
import MapKit
import SwiftUI

private enum MiniLocationMapPreviewTiming {
    static let loadingTimeoutNanoseconds: UInt64 = 8_000_000_000
}

struct MiniLocationMapView: View {
    let locationText: String
    let preferredHeight: CGFloat

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 18.4655, longitude: -66.1057),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
    @State private var marker: MapMarkerItem?
    @State private var isLoading = false
    @State private var requestedLocationText: String?
    @State private var resolveTask: Task<Void, Never>?
    @State private var loadingTimeoutTask: Task<Void, Never>?

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
        .onDisappear {
            resolveTask?.cancel()
            resolveTask = nil
            loadingTimeoutTask?.cancel()
            loadingTimeoutTask = nil
        }
    }

    private func resolveLocation() {
        let requestedLocation = locationText
        let trimmed = requestedLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            resolveTask?.cancel()
            resolveTask = nil
            loadingTimeoutTask?.cancel()
            loadingTimeoutTask = nil
            requestedLocationText = nil
            isLoading = false
            marker = nil
            return
        }
        if requestedLocationText == requestedLocation,
           isLoading || marker != nil {
            return
        }

        requestedLocationText = requestedLocation
        isLoading = true
        marker = nil
        resolveTask?.cancel()
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: MiniLocationMapPreviewTiming.loadingTimeoutNanoseconds)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard requestedLocationText == requestedLocation,
                      isLoading else { return }
                isLoading = false
                marker = nil
                resolveTask?.cancel()
                resolveTask = nil
                loadingTimeoutTask = nil
            }
        }
        resolveTask = Task {
            let coordinate = await LocationCoordinateResolver.shared.coordinate(for: requestedLocation)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard requestedLocation == locationText,
                      requestedLocationText == requestedLocation else { return }
                loadingTimeoutTask?.cancel()
                loadingTimeoutTask = nil
                isLoading = false
                resolveTask = nil
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
