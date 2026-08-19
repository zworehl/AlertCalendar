import SwiftUI

struct CalendarParticipationTexture: View {
    let status: EventParticipationStatus?

    var body: some View {
        if let status, status.usesTexturedFill {
            Canvas { context, size in
                var path = Path()
                let spacing = max(4, status.appleCalendarStripeSpacing)
                var currentX = -size.height

                while currentX <= size.width + size.height {
                    path.move(to: CGPoint(x: currentX, y: size.height))
                    path.addLine(to: CGPoint(x: currentX + size.height, y: 0))
                    currentX += spacing
                }

                context.stroke(
                    path,
                    with: .color(.black.opacity(Double(status.appleCalendarStripeAlpha))),
                    lineWidth: 1.5
                )
            }
            .allowsHitTesting(false)
        }
    }
}
