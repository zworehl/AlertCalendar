import SwiftUI

struct SlackWorkspaceAvatarPair: View, Equatable {
    let primaryImageURL: URL?
    let secondaryImageURL: URL?
    let primaryInitials: String
    let secondaryInitials: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            remoteImage(
                url: primaryImageURL,
                fallbackText: primaryInitials,
                fallbackSymbol: "person.crop.circle.fill",
                size: 40,
                cornerRadius: 20
            )

            remoteImage(
                url: secondaryImageURL,
                fallbackText: secondaryInitials,
                fallbackSymbol: "building.2.crop.circle.fill",
                size: 20,
                cornerRadius: 10
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
            )
        }
        .frame(width: 44, height: 44)
    }

    @ViewBuilder
    private func remoteImage(
        url: URL?,
        fallbackText: String,
        fallbackSymbol: String,
        size: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    fallbackImage(text: fallbackText, symbol: fallbackSymbol)
                }
            }
            .transaction { transaction in
                transaction.animation = nil
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            fallbackImage(text: fallbackText, symbol: fallbackSymbol)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private func fallbackImage(text: String, symbol: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.82))

            if !text.isEmpty {
                Text(text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}
