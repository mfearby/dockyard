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
    /// Still starting up (see `LaunchTracker`): the button stays, with an hourglass, until its first window appears.
    public var isLoading: Bool

    public init(bundleId: String?, isRegular: Bool = true, isTerminated: Bool = false,
                isHidden: Bool = false, windowCount: Int? = nil, isLoading: Bool = false) {
        self.bundleId = bundleId
        self.isRegular = isRegular
        self.isTerminated = isTerminated
        self.isHidden = isHidden
        self.windowCount = windowCount
        self.isLoading = isLoading
    }
}

/// Alphabetical order by displayed name, as Finder sorts: case-insensitive, with numbers in numeric order
/// ("Folder 2" before "Folder 10"). Items with the same name are ordered by `id`, so the order is always the same.
public enum AlphabeticalOrder {
    public static func sorted<T>(_ items: [T], name: (T) -> String, id: (T) -> String) -> [T] {
        items.sorted { a, b in
            switch name(a).localizedStandardCompare(name(b)) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: id(a) < id(b)
            }
        }
    }
}

/// What clicking an app's taskbar button does (window buttons always raise their window).
public enum AppButtonClick: Equatable {
    /// Bring the app to the front.
    case activate
    /// Show a menu of the app's windows above the button.
    case showWindowMenu

    /// The first click on an app that isn't in front just brings it forward. Once it's in front, a click lists
    /// its windows, but only when there are at least two to choose from.
    public static func action(isFrontmost: Bool, windowCount: Int) -> AppButtonClick {
        isFrontmost && windowCount >= 2 ? .showWindowMenu : .activate
    }
}

public enum AppFilter {
    /// Whether a running app belongs on the bar: ordinary apps with a bundle ID, excluding Dockyard itself,
    /// then narrowed by the user's preferences.
    public static func shouldShow(_ app: AppSnapshot, preferences: Preferences, ownBundleId: String?) -> Bool {
        guard let bundleId = app.bundleId, app.isRegular, !app.isTerminated, bundleId != ownBundleId,
              !preferences.excludedApps.contains(bundleId) else { return false }
        if app.isHidden {
            // Hidden apps are governed only by hideHiddenApps; their windows are off screen,
            // so the window check below would otherwise remove them too.
            return !preferences.hideHiddenApps
        }
        // An app that's still starting has no windows yet; keep its button so it doesn't vanish and reappear.
        if app.isLoading { return true }
        if preferences.hideAppsWithoutWindows, let count = app.windowCount, count == 0 {
            return false
        }
        return true
    }
}
