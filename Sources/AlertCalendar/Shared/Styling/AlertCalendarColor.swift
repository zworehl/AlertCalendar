import Foundation

struct AlertCalendarColor: Equatable, Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    let semanticName: String?

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0, semanticName: String? = nil) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
        self.semanticName = semanticName
    }

    func withAlphaComponent(_ alpha: Double) -> AlertCalendarColor {
        AlertCalendarColor(red: red, green: green, blue: blue, alpha: alpha, semanticName: semanticName)
    }

    static let clear = AlertCalendarColor(red: 0, green: 0, blue: 0, alpha: 0, semanticName: "clear")
    static let white = AlertCalendarColor(red: 1, green: 1, blue: 1, semanticName: "white")
    static let systemBlue = AlertCalendarColor(red: 0.25, green: 0.56, blue: 0.96, semanticName: "systemBlue")
    static let systemGray = AlertCalendarColor(red: 0.56, green: 0.56, blue: 0.58, semanticName: "systemGray")
    static let systemGreen = AlertCalendarColor(red: 0.20, green: 0.78, blue: 0.35, semanticName: "systemGreen")
    static let systemOrange = AlertCalendarColor(red: 1.00, green: 0.58, blue: 0.00, semanticName: "systemOrange")
    static let systemPink = AlertCalendarColor(red: 1.00, green: 0.22, blue: 0.45, semanticName: "systemPink")
    static let systemRed = AlertCalendarColor(red: 1.00, green: 0.23, blue: 0.19, semanticName: "systemRed")
    static let systemYellow = AlertCalendarColor(red: 1.00, green: 0.80, blue: 0.00, semanticName: "systemYellow")
    static let tertiaryLabel = AlertCalendarColor(red: 0.55, green: 0.55, blue: 0.57, alpha: 0.65, semanticName: "tertiaryLabel")
}
