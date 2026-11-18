import CoreGraphics
import Foundation

/// Messages the web UI sends through `window.webkit.messageHandlers.native.postMessage`.
public enum UIMessage: Equatable {
    // From the bar
    case ready
    case activate(bundleId: String)
    case setOrder([String])
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
        case "getSettings":
            self = .getSettings
        case "setPreferences":
            guard let p = dict["preferences"] as? [String: Any],
                  let hideHidden = p["hideHiddenApps"] as? Bool,
                  let hideWindowless = p["hideAppsWithoutWindows"] as? Bool else { return nil }
            self = .setPreferences(Preferences(hideHiddenApps: hideHidden, hideAppsWithoutWindows: hideWindowless))
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
    }

    private struct Settings: Encodable {
        let type = "settings"
        let preferences: Preferences
        let accessibilityTrusted: Bool
    }

    /// JavaScript that delivers the current app list to `window.onNative`.
    public static func stateScript(apps: [AppEntry]) -> String {
        script(State(apps: apps))
    }

    /// JavaScript that delivers the current preferences to the Options window.
    public static func settingsScript(preferences: Preferences, accessibilityTrusted: Bool) -> String {
        script(Settings(preferences: preferences, accessibilityTrusted: accessibilityTrusted))
    }

    private static func script<T: Encodable>(_ message: T) -> String {
        let json = (try? JSONEncoder().encode(message)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        return "window.onNative && window.onNative(\(json))"
    }
}

public enum BarLayout {
    /// The bar's frame: full width along the bottom edge of the screen (AppKit's origin is bottom-left).
    public static func frame(screen: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: height)
    }
}
