import Foundation

public struct History<Value> {
    public private(set) var items: [Value] = []
    private let capacity: Int
    private let same: (Value, Value) -> Bool
    public init(capacity: Int = 25, same: @escaping (Value, Value) -> Bool) {
        self.capacity = max(1, capacity)
        self.same = same
    }
    public mutating func insert(_ value: Value) {
        items.removeAll { same($0, value) }
        items.insert(value, at: 0)
        if items.count > capacity { items.removeLast(items.count - capacity) }
    }
    public mutating func trim(toByteBudget budget: Int, cost: (Value) -> Int) {
        var total = items.reduce(0) { $0 + cost($1) }
        for index in items.indices.reversed() where total > budget {
            let bytes = cost(items[index])
            if bytes > 0 { total -= bytes; items.remove(at: index) }
        }
    }
    public mutating func clear() { items.removeAll(keepingCapacity: false) }
}
