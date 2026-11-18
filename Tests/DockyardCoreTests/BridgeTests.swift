import CoreGraphics
import DockyardCore
import Foundation
import Testing

struct UIMessageTests {
    @Test func parsesSimpleMessages() {
        #expect(UIMessage(body: ["type": "ready"]) == .ready)
        #expect(UIMessage(body: ["type": "menu"]) == .menu)
    }

    @Test func parsesActivate() {
        #expect(UIMessage(body: ["type": "activate", "bundleId": "com.apple.Notes"]) == .activate(bundleId: "com.apple.Notes"))
    }

    @Test func parsesSetOrder() {
        #expect(UIMessage(body: ["type": "setOrder", "order": ["a", "b"]]) == .setOrder(["a", "b"]))
    }

    @Test func parsesOptionsWindowMessages() {
        #expect(UIMessage(body: ["type": "getSettings"]) == .getSettings)
        #expect(UIMessage(body: ["type": "requestAccessibility"]) == .requestAccessibility)
        #expect(UIMessage(body: ["type": "closeSettings"]) == .closeSettings)
    }

    @Test func parsesSetPreferences() {
        let body: [String: Any] = ["type": "setPreferences",
                                   "preferences": ["hideHiddenApps": true, "hideAppsWithoutWindows": false]]
        #expect(UIMessage(body: body) == .setPreferences(Preferences(hideHiddenApps: true, hideAppsWithoutWindows: false)))
    }

    @Test func parsesBooleansAsWebKitDeliversThem() {
        // WebKit hands JS booleans over as NSNumber.
        let body: [String: Any] = ["type": "setPreferences",
                                   "preferences": ["hideHiddenApps": NSNumber(value: false),
                                                   "hideAppsWithoutWindows": NSNumber(value: true)]]
        #expect(UIMessage(body: body) == .setPreferences(Preferences(hideHiddenApps: false, hideAppsWithoutWindows: true)))
    }

    @Test func rejectsMalformedMessages() {
        #expect(UIMessage(body: "ready") == nil)
        #expect(UIMessage(body: ["kind": "ready"]) == nil)
        #expect(UIMessage(body: ["type": "unknown"]) == nil)
        #expect(UIMessage(body: ["type": "activate"]) == nil)
        #expect(UIMessage(body: ["type": "activate", "bundleId": 42]) == nil)
        #expect(UIMessage(body: ["type": "setOrder", "order": "a,b"]) == nil)
        #expect(UIMessage(body: ["type": "setPreferences"]) == nil)
        #expect(UIMessage(body: ["type": "setPreferences", "preferences": ["hideHiddenApps": true]]) == nil)
    }
}

struct NativeMessageTests {
    /// Extracts and decodes the JSON argument passed to window.onNative.
    private func payload(_ script: String) throws -> [String: Any] {
        let prefix = "window.onNative && window.onNative("
        #expect(script.hasPrefix(prefix) && script.hasSuffix(")"))
        let json = script.dropFirst(prefix.count).dropLast()
        return try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test func stateHasTheShapeTheUIExpects() throws {
        let entry = AppEntry(bundleId: "com.apple.Notes", name: "Notes", icon: "data:image/png;base64,AA==", active: true)
        let msg = try payload(NativeMessage.stateScript(apps: [entry]))
        #expect(msg["type"] as? String == "state")
        let apps = try #require(msg["apps"] as? [[String: Any]])
        #expect(apps.count == 1)
        #expect(apps[0]["bundleId"] as? String == "com.apple.Notes")
        #expect(apps[0]["name"] as? String == "Notes")
        #expect(apps[0]["icon"] as? String == "data:image/png;base64,AA==")
        #expect(apps[0]["active"] as? Bool == true)
    }

    @Test func settingsHaveTheShapeTheUIExpects() throws {
        let script = NativeMessage.settingsScript(
            preferences: Preferences(hideHiddenApps: true, hideAppsWithoutWindows: false), accessibilityTrusted: false)
        let msg = try payload(script)
        #expect(msg["type"] as? String == "settings")
        #expect(msg["accessibilityTrusted"] as? Bool == false)
        let prefs = try #require(msg["preferences"] as? [String: Any])
        #expect(prefs["hideHiddenApps"] as? Bool == true)
        #expect(prefs["hideAppsWithoutWindows"] as? Bool == false)
    }

    @Test func namesWithQuotesAndSlashesStaySafe() throws {
        let name = #"Tom's "App" </script> \ é"#
        let msg = try payload(NativeMessage.stateScript(apps: [AppEntry(bundleId: "x", name: name, icon: "", active: false)]))
        let apps = try #require(msg["apps"] as? [[String: Any]])
        #expect(apps[0]["name"] as? String == name)
    }
}

struct BarLayoutTests {
    @Test func spansTheBottomOfTheScreen() {
        let frame = BarLayout.frame(screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), height: 40)
        #expect(frame == CGRect(x: 0, y: 0, width: 1920, height: 40))
    }

    @Test func followsAnOffsetScreen() {
        // A second display placed to the left of and below the main one.
        let frame = BarLayout.frame(screen: CGRect(x: -2560, y: -200, width: 2560, height: 1440), height: 40)
        #expect(frame == CGRect(x: -2560, y: -200, width: 2560, height: 40))
    }
}
