import CoreGraphics
import Foundation

/// Messages the web UI sends through `window.webkit.messageHandlers.native.postMessage`.
public enum UIMessage: Equatable {
    // From the bar
    case ready
    /// `id` is a button ID: see `ButtonID`.
    case activate(id: String)
    case setOrder([String])
    case setCollapsed(Bool)
    /// Where the bar's tooltip targets are, sent whenever the buttons change or move.
    case setTooltips([TooltipTarget])
    case menu
    // From the Options window
    case getSettings
    case setPreferences(Preferences)
    case requestAccessibility
    case resizeSettings(height: Double)
    case closeSettings

    /// Parses a message body as WebKit delivers it (a JS object becomes `[String: Any]`). Returns nil for anything malformed.
    public init?(body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "ready":
            self = .ready
        case "menu":
            self = .menu
        case "activate":
            guard let id = dict["id"] as? String else { return nil }
            self = .activate(id: id)
        case "setOrder":
            guard let order = dict["order"] as? [String] else { return nil }
            self = .setOrder(order)
        case "setCollapsed":
            guard let collapsed = dict["collapsed"] as? Bool else { return nil }
            self = .setCollapsed(collapsed)
        case "setTooltips":
            guard let items = dict["tooltips"] as? [Any] else { return nil }
            self = .setTooltips(items.compactMap(TooltipTarget.init(body:)))
        case "getSettings":
            self = .getSettings
        case "setPreferences":
            guard let p = dict["preferences"] as? [String: Any],
                  let hideHidden = p["hideHiddenApps"] as? Bool,
                  let hideWindowless = p["hideAppsWithoutWindows"] as? Bool,
                  // JS numbers arrive as NSNumber and may be fractional, so round rather than require an Int.
                  let height = (p["barHeight"] as? NSNumber)?.doubleValue, height.isFinite,
                  let space = (p["screenSpace"] as? String).flatMap(ScreenSpace.init(rawValue:)),
                  let separate = p["separateWindows"] as? Bool else { return nil }
            self = .setPreferences(Preferences(hideHiddenApps: hideHidden, hideAppsWithoutWindows: hideWindowless,
                                               barHeight: Int(height.rounded()), screenSpace: space,
                                               separateWindows: separate))
        case "requestAccessibility":
            self = .requestAccessibility
        case "resizeSettings":
            guard let height = (dict["height"] as? NSNumber)?.doubleValue, height.isFinite else { return nil }
            self = .resizeSettings(height: height)
        case "closeSettings":
            self = .closeSettings
        default:
            return nil
        }
    }
}

/// An element on the bar that shows a tooltip on hover, in the bar's coordinates (points from its left edge).
public struct TooltipTarget: Equatable {
    public var id: String
    public var text: String
    public var left: Double
    public var width: Double

    public init(id: String, text: String, left: Double, width: Double) {
        self.id = id
        self.text = text
        self.left = left
        self.width = width
    }

    /// Parses one entry as WebKit delivers it; nil if malformed, so one bad entry doesn't drop the rest.
    init?(body: Any) {
        guard let dict = body as? [String: Any],
              let id = dict["id"] as? String, let text = dict["text"] as? String,
              let left = (dict["left"] as? NSNumber)?.doubleValue, left.isFinite,
              let width = (dict["width"] as? NSNumber)?.doubleValue, width.isFinite else { return nil }
        self.init(id: id, text: text, left: left, width: width)
    }

    /// The target under `x`, ignoring hidden (zero-width) elements and empty text.
    public static func hit(_ x: Double, in targets: [TooltipTarget]) -> TooltipTarget? {
        targets.first { $0.width > 0 && !$0.text.isEmpty && x >= $0.left && x < $0.left + $0.width }
    }

    /// Where to put a tooltip of `size`: just above the bar, its left edge lined up with the target's
    /// (`targetLeft`, in screen coordinates), and kept within the screen. AppKit coordinates (origin bottom-left).
    public static func frame(size: CGSize, targetLeft: CGFloat, barTop: CGFloat, screen: CGRect) -> CGRect {
        let margin: CGFloat = 2
        let x = min(max(targetLeft, screen.minX + margin), screen.maxX - size.width - margin)
        return CGRect(x: x, y: barTop + margin, width: size.width, height: size.height)
    }
}

/// Identifies a button on the bar: an app (its bundle ID) or one of its windows ("bundleId#serial").
public enum ButtonID {
    public static func app(_ bundleId: String) -> String { bundleId }

    public static func window(_ bundleId: String, serial: Int) -> String { "\(bundleId)#\(serial)" }

    /// Splits an ID into its bundle ID and window serial (nil for an app button). Bundle IDs never contain "#".
    public static func parse(_ id: String) -> (bundleId: String, window: Int?) {
        guard let hash = id.lastIndex(of: "#"), let serial = Int(id[id.index(after: hash)...]) else { return (id, nil) }
        return (String(id[..<hash]), serial)
    }
}

/// One button on the bar, as sent to the UI. Field names must match `AppInfo` in web/src/bridge.ts.
public struct AppEntry: Codable, Equatable {
    /// Unique per button; see `ButtonID`.
    public var id: String
    public var bundleId: String
    /// The button's label: the app name, or the window title.
    public var name: String
    /// Tooltip text.
    public var title: String
    public var icon: String
    public var active: Bool

    public init(id: String? = nil, bundleId: String, name: String, title: String? = nil, icon: String, active: Bool) {
        self.id = id ?? ButtonID.app(bundleId)
        self.bundleId = bundleId
        self.name = name
        self.title = title ?? name
        self.icon = icon
        self.active = active
    }
}

public enum WindowLabel {
    /// A window button's label: its title, or the app name for untitled windows.
    public static func name(title: String?, appName: String) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? appName : trimmed
    }
}

public enum NativeMessage {
    private struct State: Encodable {
        let type = "state"
        let apps: [AppEntry]
        let collapsed: Bool
    }

    private struct Settings: Encodable {
        let type = "settings"
        let preferences: Preferences
        let accessibilityTrusted: Bool
        let dockHeight: Int
        let barHeightMin = Preferences.barHeightRange.lowerBound
        let barHeightMax = Preferences.barHeightRange.upperBound
    }

    /// JavaScript that delivers the current app list, and whether the bar is retracted, to `window.onNative`.
    public static func stateScript(apps: [AppEntry], collapsed: Bool = false) -> String {
        script(State(apps: apps, collapsed: collapsed))
    }

    /// JavaScript that delivers the current preferences to the Options window.
    /// `dockHeight` is the space the Dock reserves at the bottom of the screen, or 0 if it reserves none.
    public static func settingsScript(preferences: Preferences, accessibilityTrusted: Bool, dockHeight: Int) -> String {
        script(Settings(preferences: preferences, accessibilityTrusted: accessibilityTrusted, dockHeight: dockHeight))
    }

    private static func script<T: Encodable>(_ message: T) -> String {
        let json = (try? JSONEncoder().encode(message)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        return "window.onNative && window.onNative(\(json))"
    }
}

public enum BarLayout {
    /// Width of the retracted bar, which shows only the toggle button: 4pt gap + 12pt button + 2pt edge, the same
    /// as the toggle's area on the full bar, so the button doesn't move. Must match `body.collapsed` in web/src/style.css.
    public static let collapsedWidth: CGFloat = 18

    /// The bar's frame along the bottom edge of the screen (AppKit's origin is bottom-left): full width,
    /// or when collapsed, a thin strip in the bottom-right corner so the Dock and screen edge are uncovered.
    public static func frame(screen: CGRect, height: CGFloat, collapsed: Bool = false) -> CGRect {
        guard collapsed else {
            return CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: height)
        }
        let width = min(collapsedWidth, screen.width)
        return CGRect(x: screen.maxX - width, y: screen.minY, width: width, height: height)
    }

    /// Height the Dock reserves along the bottom of a screen: the gap between the screen's full frame
    /// and its visible frame. 0 when the Dock is hidden, on another edge, or on another display.
    public static func dockHeight(screen: CGRect, visible: CGRect) -> Int {
        max(0, Int((visible.minY - screen.minY).rounded()))
    }
}
