public enum AppOrdering {
    /// Sorts items by their position in `savedOrder`. Items not in it go last, keeping their original relative order.
    public static func sorted<T>(_ items: [T], by savedOrder: [String], id: (T) -> String) -> [T] {
        var rank: [String: Int] = [:]
        for (i, id) in savedOrder.enumerated() where rank[id] == nil { rank[id] = i }
        return items.enumerated().sorted { a, b in
            let ra = rank[id(a.element)] ?? Int.max
            let rb = rank[id(b.element)] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    /// Combines the order the UI just sent (running apps only) with the saved order,
    /// so apps that aren't running keep a remembered position, after the running ones.
    public static func merged(newOrder: [String], into saved: [String]) -> [String] {
        let running = Set(newOrder)
        return newOrder + saved.filter { !running.contains($0) }
    }
}

public enum AppFilter {
    /// Whether a running app belongs on the bar: ordinary apps with a bundle ID, excluding Dockyard itself.
    public static func shouldShow(bundleId: String?, isRegular: Bool, isTerminated: Bool, ownBundleId: String?) -> Bool {
        guard let bundleId, isRegular, !isTerminated else { return false }
        return bundleId != ownBundleId
    }
}
