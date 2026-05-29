import AppKit

extension AlertCalendarColor {
    init(nsColor: NSColor) {
        let resolved = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        self.init(
            red: Double(resolved.redComponent),
            green: Double(resolved.greenComponent),
            blue: Double(resolved.blueComponent),
            alpha: Double(resolved.alphaComponent)
        )
    }

    var nsColor: NSColor {
        let baseColor: NSColor = {
            switch semanticName {
            case "clear":
                return .clear
            case "white":
                return .white
            case "systemBlue":
                return .systemBlue
            case "systemGray":
                return .systemGray
            case "systemGreen":
                return .systemGreen
            case "systemOrange":
                return .systemOrange
            case "systemPink":
                return .systemPink
            case "systemRed":
                return .systemRed
            case "systemYellow":
                return .systemYellow
            case "tertiaryLabel":
                return .tertiaryLabelColor
            default:
                return NSColor(
                    calibratedRed: CGFloat(red),
                    green: CGFloat(green),
                    blue: CGFloat(blue),
                    alpha: CGFloat(alpha)
                )
            }
        }()

        return baseColor.withAlphaComponent(CGFloat(alpha))
    }
}
