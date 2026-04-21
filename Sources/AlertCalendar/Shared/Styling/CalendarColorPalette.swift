import AppKit
import Foundation

struct CalendarColorOption: Identifiable, Hashable {
    let id: String
    let name: String
    let color: NSColor
}

enum CalendarColorPalette {
    static let options: [CalendarColorOption] = [
        CalendarColorOption(id: "red", name: "Red", color: NSColor(calibratedRed: 0.97, green: 0.27, blue: 0.22, alpha: 1.0)),
        CalendarColorOption(id: "orange", name: "Orange", color: NSColor(calibratedRed: 0.98, green: 0.58, blue: 0.20, alpha: 1.0)),
        CalendarColorOption(id: "yellow", name: "Yellow", color: NSColor(calibratedRed: 0.96, green: 0.80, blue: 0.26, alpha: 1.0)),
        CalendarColorOption(id: "green", name: "Green", color: NSColor(calibratedRed: 0.37, green: 0.77, blue: 0.42, alpha: 1.0)),
        CalendarColorOption(id: "mint", name: "Mint", color: NSColor(calibratedRed: 0.30, green: 0.80, blue: 0.74, alpha: 1.0)),
        CalendarColorOption(id: "teal", name: "Teal", color: NSColor(calibratedRed: 0.22, green: 0.73, blue: 0.79, alpha: 1.0)),
        CalendarColorOption(id: "blue", name: "Blue", color: NSColor(calibratedRed: 0.25, green: 0.56, blue: 0.96, alpha: 1.0)),
        CalendarColorOption(id: "indigo", name: "Indigo", color: NSColor(calibratedRed: 0.37, green: 0.43, blue: 0.93, alpha: 1.0)),
        CalendarColorOption(id: "purple", name: "Purple", color: NSColor(calibratedRed: 0.68, green: 0.39, blue: 0.93, alpha: 1.0)),
        CalendarColorOption(id: "pink", name: "Pink", color: NSColor(calibratedRed: 0.97, green: 0.45, blue: 0.70, alpha: 1.0)),
        CalendarColorOption(id: "brown", name: "Brown", color: NSColor(calibratedRed: 0.64, green: 0.50, blue: 0.39, alpha: 1.0)),
        CalendarColorOption(id: "gray", name: "Gray", color: NSColor(calibratedWhite: 0.57, alpha: 1.0)),
    ]

    static func color(for id: String) -> NSColor {
        options.first(where: { $0.id == id })?.color ?? options[6].color
    }
}
