import Foundation

/// How the taskbar avoids covering windows, given macOS won't let apps reserve screen space.
public enum ScreenSpace: String, Codable, Equatable {
    /// The Dock stays visible along the bottom, so macOS keeps windows above it, and the bar covers the Dock.
    case coverDock
    /// Dockyard moves and resizes other apps' windows (via Accessibility) so they stay above the bar.
    case moveWindows
}

/// The taskbar's colour scheme.
public enum Theme: String, Codable, Equatable {
    case light
    case dark
}

/// The lists the user manages in Options with Add… and Remove. All hold bundle IDs except `menuFolders` (paths).
public enum AppList: String, Codable, Equatable {
    /// Apps that never get a button on the bar.
    case excludedApps
    /// Launcher icons between the menu button and the taskbar buttons.
    case quickLaunch
    /// Apps added to the menu button's menu.
    case menuApps
    /// Folders added to the menu button's menu, as absolute paths.
    case menuFolders
}

/// Options the user can toggle on the Options screen.
public struct Preferences: Codable, Equatable {
    /// Leave apps hidden with Command-H off the bar.
    public var hideHiddenApps: Bool
    /// Leave apps with no open windows (such as Finder with every window closed) off the bar.
    public var hideAppsWithoutWindows: Bool
    /// Bar height in points. Always within `barHeightRange`.
    public var barHeight: Int {
        didSet { barHeight = Preferences.clampBarHeight(barHeight) }
    }

    public var screenSpace: ScreenSpace
    /// Give each window its own button (labelled with the window title) instead of one button per app.
    public var separateWindows: Bool
    /// Bundle IDs of apps that never get a button on the bar, in the order the user added them.
    public var excludedApps: [String]
    /// Bundle IDs of the Quick Launch icons, left to right.
    public var quickLaunch: [String]
    /// Bundle IDs of apps in the menu button's menu, top to bottom.
    public var menuApps: [String]
    /// Paths of folders in the menu button's menu, top to bottom.
    public var menuFolders: [String]
    public var theme: Theme

    public static let defaultBarHeight = 40
    /// Below 28pt the labels no longer fit; above 64pt the bar wastes space.
    public static let barHeightRange = 28...64

    public static func clampBarHeight(_ height: Int) -> Int {
        min(max(height, barHeightRange.lowerBound), barHeightRange.upperBound)
    }

    public init(hideHiddenApps: Bool = false, hideAppsWithoutWindows: Bool = false,
                barHeight: Int = Preferences.defaultBarHeight, screenSpace: ScreenSpace = .coverDock,
                separateWindows: Bool = false, excludedApps: [String] = [], quickLaunch: [String] = [],
                menuApps: [String] = [], menuFolders: [String] = [], theme: Theme = .light) {
        self.hideHiddenApps = hideHiddenApps
        self.hideAppsWithoutWindows = hideAppsWithoutWindows
        self.barHeight = Preferences.clampBarHeight(barHeight)
        self.screenSpace = screenSpace
        self.separateWindows = separateWindows
        self.excludedApps = excludedApps
        self.quickLaunch = quickLaunch
        self.menuApps = menuApps
        self.menuFolders = menuFolders
        self.theme = theme
    }

    /// The bundle IDs (or for `menuFolders`, paths) in `list`.
    public func items(in list: AppList) -> [String] {
        switch list {
        case .excludedApps: excludedApps
        case .quickLaunch: quickLaunch
        case .menuApps: menuApps
        case .menuFolders: menuFolders
        }
    }

    /// Appends `item` (a bundle ID, or a path for `menuFolders`) to `list` unless it's already there.
    /// Returns whether it was added.
    @discardableResult
    public mutating func add(_ item: String, to list: AppList) -> Bool {
        guard !items(in: list).contains(item) else { return false }
        switch list {
        case .excludedApps: excludedApps.append(item)
        case .quickLaunch: quickLaunch.append(item)
        case .menuApps: menuApps.append(item)
        case .menuFolders: menuFolders.append(item)
        }
        return true
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hideHiddenApps = try c.decodeIfPresent(Bool.self, forKey: .hideHiddenApps) ?? false
        hideAppsWithoutWindows = try c.decodeIfPresent(Bool.self, forKey: .hideAppsWithoutWindows) ?? false
        barHeight = Preferences.clampBarHeight(
            try c.decodeIfPresent(Int.self, forKey: .barHeight) ?? Preferences.defaultBarHeight)
        // An unknown value (e.g. from a newer version) falls back to the default instead of failing the whole file.
        screenSpace = ((try? c.decodeIfPresent(ScreenSpace.self, forKey: .screenSpace)) ?? nil) ?? .coverDock
        separateWindows = try c.decodeIfPresent(Bool.self, forKey: .separateWindows) ?? false
        excludedApps = try c.decodeIfPresent([String].self, forKey: .excludedApps) ?? []
        quickLaunch = try c.decodeIfPresent([String].self, forKey: .quickLaunch) ?? []
        menuApps = try c.decodeIfPresent([String].self, forKey: .menuApps) ?? []
        menuFolders = try c.decodeIfPresent([String].self, forKey: .menuFolders) ?? []
        theme = ((try? c.decodeIfPresent(Theme.self, forKey: .theme)) ?? nil) ?? .light
    }
}

/// User settings stored in ~/.config/dockyard/config.json.
public struct Config: Codable, Equatable {
    /// Bundle IDs in the order the user arranged them on the bar.
    public var order: [String]
    public var preferences: Preferences
    /// Whether the bar is retracted to just its toggle button. Remembered across restarts.
    public var collapsed: Bool

    public init(order: [String] = [], preferences: Preferences = Preferences(), collapsed: Bool = false) {
        self.order = order
        self.preferences = preferences
        self.collapsed = collapsed
    }

    // Missing keys fall back to defaults so older config files keep loading as fields are added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = try c.decodeIfPresent([String].self, forKey: .order) ?? []
        preferences = try c.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
    }
}

public struct ConfigStore {
    public static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/dockyard/config.json")

    public let url: URL

    public init(url: URL = ConfigStore.defaultURL) {
        self.url = url
    }

    /// Returns defaults if the file is missing or unreadable, so a bad config never stops the bar starting.
    public func load() -> Config {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        return config
    }

    public func save(_ config: Config) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
