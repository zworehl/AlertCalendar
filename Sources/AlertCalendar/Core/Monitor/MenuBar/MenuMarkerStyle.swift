import Foundation

enum MenuMarkerStyle: Equatable {
    case color(AlertCalendarColor)
    case reminder(AlertCalendarColor)
    case birthday(AlertCalendarColor)
    case allDay(AlertCalendarColor)
    case gameStore(GameStore)
    case travel(AlertCalendarColor)
    case sunrise
    case solarNoon
    case sunset
    case solarMidnight
    case perihelion
    case aphelion
    case marchEquinox
    case juneSolstice
    case septemberEquinox
    case decemberSolstice
    case newMoon
    case waxingCrescent
    case firstQuarter
    case waxingGibbous
    case fullMoon
    case waningGibbous
    case lastQuarter
    case waningCrescent

    static func == (lhs: MenuMarkerStyle, rhs: MenuMarkerStyle) -> Bool {
        switch (lhs, rhs) {
        case let (.color(left), .color(right)):
            return left == right
        case let (.reminder(left), .reminder(right)):
            return left == right
        case let (.birthday(left), .birthday(right)):
            return left == right
        case let (.allDay(left), .allDay(right)):
            return left == right
        case let (.gameStore(left), .gameStore(right)):
            return left == right
        case let (.travel(left), .travel(right)):
            return left == right
        case (.sunrise, .sunrise),
            (.solarNoon, .solarNoon),
            (.sunset, .sunset),
            (.solarMidnight, .solarMidnight),
            (.perihelion, .perihelion),
            (.aphelion, .aphelion),
            (.marchEquinox, .marchEquinox),
            (.juneSolstice, .juneSolstice),
            (.septemberEquinox, .septemberEquinox),
            (.decemberSolstice, .decemberSolstice),
            (.newMoon, .newMoon),
            (.waxingCrescent, .waxingCrescent),
            (.firstQuarter, .firstQuarter),
            (.waxingGibbous, .waxingGibbous),
            (.fullMoon, .fullMoon),
            (.waningGibbous, .waningGibbous),
            (.lastQuarter, .lastQuarter),
            (.waningCrescent, .waningCrescent):
            return true
        default:
            return false
        }
    }
}
