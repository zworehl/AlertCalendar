import Foundation

struct CalendarColorOption: Identifiable, Hashable {
    let id: String
    let name: String
    let color: AlertCalendarColor
}

enum CalendarColorPalette {
    static let options: [CalendarColorOption] = [
        CalendarColorOption(id: "red", name: "Red", color: AlertCalendarColor(red: 0.97, green: 0.27, blue: 0.22)),
        CalendarColorOption(id: "orange", name: "Orange", color: AlertCalendarColor(red: 0.98, green: 0.58, blue: 0.20)),
        CalendarColorOption(id: "yellow", name: "Yellow", color: AlertCalendarColor(red: 0.96, green: 0.80, blue: 0.26)),
        CalendarColorOption(id: "green", name: "Green", color: AlertCalendarColor(red: 0.37, green: 0.77, blue: 0.42)),
        CalendarColorOption(id: "mint", name: "Mint", color: AlertCalendarColor(red: 0.30, green: 0.80, blue: 0.74)),
        CalendarColorOption(id: "teal", name: "Teal", color: AlertCalendarColor(red: 0.22, green: 0.73, blue: 0.79)),
        CalendarColorOption(id: "blue", name: "Blue", color: AlertCalendarColor(red: 0.25, green: 0.56, blue: 0.96)),
        CalendarColorOption(id: "indigo", name: "Indigo", color: AlertCalendarColor(red: 0.37, green: 0.43, blue: 0.93)),
        CalendarColorOption(id: "purple", name: "Purple", color: AlertCalendarColor(red: 0.68, green: 0.39, blue: 0.93)),
        CalendarColorOption(id: "pink", name: "Pink", color: AlertCalendarColor(red: 0.97, green: 0.45, blue: 0.70)),
        CalendarColorOption(id: "brown", name: "Brown", color: AlertCalendarColor(red: 0.64, green: 0.50, blue: 0.39)),
        CalendarColorOption(id: "gray", name: "Gray", color: AlertCalendarColor(red: 0.57, green: 0.57, blue: 0.57)),
    ]

    static func color(for id: String) -> AlertCalendarColor {
        options.first(where: { $0.id == id })?.color ?? options[6].color
    }
}
