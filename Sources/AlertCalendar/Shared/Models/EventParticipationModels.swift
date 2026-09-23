import CoreGraphics
import Foundation

struct EventParticipationVisualStyle: Equatable {
    let backgroundAlpha: CGFloat
    let textAlpha: CGFloat
    let stripeAlpha: CGFloat
    let stripeSpacing: CGFloat
    let stripeWidth: CGFloat

    var usesTexture: Bool {
        stripeAlpha > 0 && stripeSpacing > 0 && stripeWidth > 0
    }

    static func solid(backgroundAlpha: CGFloat, textAlpha: CGFloat) -> Self {
        Self(
            backgroundAlpha: backgroundAlpha,
            textAlpha: textAlpha,
            stripeAlpha: 0,
            stripeSpacing: 0,
            stripeWidth: 0
        )
    }

    static func textured(
        backgroundAlpha: CGFloat,
        textAlpha: CGFloat,
        stripeAlpha: CGFloat
    ) -> Self {
        let stripeSpacing: CGFloat = 7
        return Self(
            backgroundAlpha: backgroundAlpha,
            textAlpha: textAlpha,
            stripeAlpha: stripeAlpha,
            stripeSpacing: stripeSpacing,
            stripeWidth: stripeSpacing * 0.58
        )
    }
}

enum CalendarParticipationTexturePattern {
    static func path(in size: CGSize, style: EventParticipationVisualStyle) -> CGPath {
        let path = CGMutablePath()
        guard style.usesTexture, size.width > 0, size.height > 0 else {
            return path
        }

        var currentX = -size.height
        while currentX <= size.width + size.height {
            path.move(to: CGPoint(x: currentX, y: size.height))
            path.addLine(to: CGPoint(x: currentX + style.stripeWidth, y: size.height))
            path.addLine(to: CGPoint(x: currentX + size.height + style.stripeWidth, y: 0))
            path.addLine(to: CGPoint(x: currentX + size.height, y: 0))
            path.closeSubpath()
            currentX += style.stripeSpacing
        }

        return path
    }
}

enum EventParticipationStatus: String, Equatable {
    case accepted
    case tentative
    case pending
    case declined

    var appleCalendarStyle: EventParticipationVisualStyle {
        switch self {
        case .accepted:
            return .solid(backgroundAlpha: 0.30, textAlpha: 1.0)
        case .tentative:
            return .textured(backgroundAlpha: 0.30, textAlpha: 0.88, stripeAlpha: 0.16)
        case .pending:
            return .textured(backgroundAlpha: 0.24, textAlpha: 0.74, stripeAlpha: 0.18)
        case .declined:
            return .textured(backgroundAlpha: 0.20, textAlpha: 0.62, stripeAlpha: 0.24)
        }
    }
}
