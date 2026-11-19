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

    /// The app order implied by the bar's button order: each app's position is that of its first button.
    public static func bundleOrder(fromButtonIDs ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.map { ButtonID.parse($0).bundleId }.filter { seen.insert($0).inserted }
    }
}

/// What the bar needs to know about a running app to decide whether to show it.
public struct AppSnapshot: Equatable {
    public var bundleId: String?
    public var isRegular: Bool
    public var isTerminated: Bool
    public var isHidden: Bool
    /// Number of open windows. Only needed when `hideAppsWithoutWindows` is on, so callers can skip counting otherwise.
    public var windowCount: Int?

    public init(bundleId: String?, isRegular: Bool = true, isTerminated: Bool = false,
                isHidden: Bool = false, windowCount: Int? = nil) {
        self.bundleId = bundleId
        self.isRegular = isRegular
        self.isTerminated = isTerminated
        self.isHidden = isHidden
        self.windowCount = windowCount
    }
}

public enum AppFilter {
    /// Whether a running app belongs on the bar: ordinary apps with a bundle ID, excluding Dockyard itself,
    /// then narrowed by the user's preferences.
    public static func shouldShow(_ app: AppSnapshot, preferences: Preferences, ownBundleId: String?) -> Bool {
        guard let bundleId = app.bundleId, app.isRegular, !app.isTerminated, bundleId != ownBundleId else { return false }
        if app.isHidden {
            // Hidden apps are governed only by hideHiddenApps; their windows are off screen,
            // so the window check below would otherwise remove them too.
            return !preferences.hideHiddenApps
        }
        if preferences.hideAppsWithoutWindows, let count = app.windowCount, count == 0 {
            return false
        }
        return true
    }
}
