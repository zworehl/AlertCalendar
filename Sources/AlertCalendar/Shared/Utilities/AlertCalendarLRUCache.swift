import Foundation

struct AlertCalendarLRUCache<Key: Hashable, Value> {
    let capacity: Int

    private var storage: [Key: Value] = [:]
    private var recency: [Key] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    var count: Int {
        storage.count
    }

    mutating func value(forKey key: Key) -> Value? {
        guard let value = storage[key] else { return nil }
        markRecentlyUsed(key)
        return value
    }

    mutating func insert(_ value: Value, forKey key: Key) {
        storage[key] = value
        markRecentlyUsed(key)

        while storage.count > capacity, let leastRecentlyUsedKey = recency.first {
            recency.removeFirst()
            storage.removeValue(forKey: leastRecentlyUsedKey)
        }
    }

    @discardableResult
    mutating func removeValue(forKey key: Key) -> Value? {
        recency.removeAll { $0 == key }
        return storage.removeValue(forKey: key)
    }

    mutating func removeAll(keepingCapacity: Bool = false) {
        storage.removeAll(keepingCapacity: keepingCapacity)
        recency.removeAll(keepingCapacity: keepingCapacity)
    }

    func contains(_ key: Key) -> Bool {
        storage[key] != nil
    }

    private mutating func markRecentlyUsed(_ key: Key) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}
