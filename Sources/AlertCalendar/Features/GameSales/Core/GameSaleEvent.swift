import Foundation

struct GameSaleEvent: Identifiable, Hashable, Codable, Sendable {
    let store: GameStore
    let sourceID: String
    let title: String
    let startDate: Date
    let endDateExclusive: Date
    let officialURL: URL

    init(
        store: GameStore,
        sourceID: String,
        title: String,
        startDate: Date,
        endDateExclusive: Date,
        officialURL: URL
    ) {
        self.store = store
        self.sourceID = sourceID
        self.title = title
        self.startDate = startDate
        self.endDateExclusive = endDateExclusive
        self.officialURL = officialURL
    }

    var id: String {
        "\(store.rawValue):\(sourceID)"
    }

    var isAllDay: Bool { true }
}
