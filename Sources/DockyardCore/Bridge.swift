import CoreGraphics
import Foundation

/// Messages the web UI sends through `window.webkit.messageHandlers.native.postMessage`.
public enum UIMessage: Equatable {
    // From the bar
    case ready
    case activate(bundleId: String)
    case setOrder([String])
    case setCollapsed(Bool)
    case menu
    // From the Options window
    case getSettings
    case setPreferences(Preferences)
    case requestAccessibility
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
            guard let id = dict["bundleId"] as? String else { return nil }
            self = .activate(bundleId: id)
        case "setOrder":
            guard let order = dict["order"] as? [String] else { return nil }
            self = .setOrder(order)
        case "setCollapsed":
            guard let collapsed = dict["collapsed"] as? Bool else { return nil }
            self = .setCollapsed(collapsed)
        case "getSettings":
            self = .getSettings
        case "setPreferences":
            guard let p = dict["preferences"] as? [String: Any],
                  let hideHidden = p["hideHiddenApps"] as? Bool,
                  let hideWindowless = p["hideAppsWithoutWindows"] as? Bool,
                  // JS numbers arrive as NSNumber and may be fractional, so round rather than require an Int.
                  let height = (p["barHeight"] as? NSNumber)?.doubleValue, height.isFinite else { return nil }
            self = .setPreferences(Preferences(hideHiddenApps: hideHidden, hideAppsWithoutWindows: hideWindowless,
                                               barHeight: Int(height.rounded())))
        case "requestAccessibility":
            self = .requestAccessibility
        case "closeSettings":
            self = .closeSettings
        default:
            return nil
        }
    }
}

/// One button on the bar, as sent to the UI. Field names must match `AppInfo` in web/src/bridge.ts.
public struct AppEntry: Codable, Equatable {
    public var bundleId: String
    public var name: String
    public var icon: String
    public var active: Bool

    public init(bundleId: String, name: String, icon: String, active: Bool) {
        self.bundleId = bundleId
        self.name = name
        self.icon = icon
        self.active = active
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
    /// Width of the retracted bar, which shows only the toggle button. Must match `body.collapsed` in web/src/style.css.
    public static let collapsedWidth: CGFloat = 16

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
