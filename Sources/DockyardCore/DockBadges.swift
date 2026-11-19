import Foundation

/// Matches the Dock's badges (the red count on an app's Dock icon) to running apps.
///
/// Apps set badges on their own Dock tile, and macOS offers no public API to read another app's badge.
/// The Dock exposes each item's badge through Accessibility as `AXStatusLabel`, alongside the app's URL,
/// so the host reads those and this matches them to bundle IDs.
public enum DockBadges {
    /// A badge as the Dock reports it: the app bundle's path and the label text.
    public struct Item: Equatable {
        public var appPath: String
        public var label: String?

        public init(appPath: String, label: String?) {
            self.appPath = appPath
            self.label = label
        }
    }

    /// The text to show, or nil for no badge. Labels are usually counts ("1", "99+") but can be any short text.
    public static func normalize(_ label: String?) -> String? {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Badge text by bundle ID. `apps` maps each running app's bundle path to its bundle ID.
    /// Paths are compared after standardising, so "/Applications/Foo.app/" matches "/Applications/Foo.app".
    public static func match(_ items: [Item], apps: [String: String]) -> [String: String] {
        let byPath = Dictionary(apps.map { (standardize($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        var badges: [String: String] = [:]
        for item in items {
            guard let label = normalize(item.label), let id = byPath[standardize(item.appPath)] else { continue }
            badges[id] = label
        }
        return badges
    }

    private static func standardize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
