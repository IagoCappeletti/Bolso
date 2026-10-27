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
    public mutating func clear() { items.removeAll(keepingCapacity: false) }
}
