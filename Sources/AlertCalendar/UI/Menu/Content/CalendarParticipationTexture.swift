import SwiftUI

struct CalendarParticipationTexture: View {
    let status: EventParticipationStatus?

    var body: some View {
        if let style = status?.appleCalendarStyle, style.usesTexture {
            Canvas { context, size in
                context.fill(
                    Path(CalendarParticipationTexturePattern.path(in: size, style: style)),
                    with: .color(.black.opacity(Double(style.stripeAlpha)))
                )
            }
            .allowsHitTesting(false)
        }
    }
}
