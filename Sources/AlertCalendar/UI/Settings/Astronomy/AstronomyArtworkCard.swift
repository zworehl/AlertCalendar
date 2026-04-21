import AppKit
import SwiftUI

struct AstronomyArtworkCard<Artwork: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let artwork: () -> Artwork

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            artwork()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
    }
}
