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

    @Test func parsesSetCollapsed() {
        #expect(UIMessage(body: ["type": "setCollapsed", "collapsed": true]) == .setCollapsed(true))
        #expect(UIMessage(body: ["type": "setCollapsed", "collapsed": NSNumber(value: false)]) == .setCollapsed(false))
    }

    @Test func parsesOptionsWindowMessages() {
        #expect(UIMessage(body: ["type": "getSettings"]) == .getSettings)
        #expect(UIMessage(body: ["type": "requestAccessibility"]) == .requestAccessibility)
        #expect(UIMessage(body: ["type": "closeSettings"]) == .closeSettings)
    }

    private func setPreferences(height: Any = 40, screenSpace: Any = "coverDock") -> [String: Any] {
        ["type": "setPreferences",
         "preferences": ["hideHiddenApps": true, "hideAppsWithoutWindows": false, "barHeight": height,
                         "screenSpace": screenSpace]]
    }

    @Test func parsesSetPreferences() {
        #expect(UIMessage(body: setPreferences(height: 36))
            == .setPreferences(Preferences(hideHiddenApps: true, hideAppsWithoutWindows: false, barHeight: 36)))
    }

    @Test func parsesValuesAsWebKitDeliversThem() {
        // WebKit hands JS booleans and numbers over as NSNumber.
        let body: [String: Any] = ["type": "setPreferences",
                                   "preferences": ["hideHiddenApps": NSNumber(value: false),
                                                   "hideAppsWithoutWindows": NSNumber(value: true),
                                                   "barHeight": NSNumber(value: 36.0),
                                                   "screenSpace": "coverDock"]]
        #expect(UIMessage(body: body)
            == .setPreferences(Preferences(hideHiddenApps: false, hideAppsWithoutWindows: true, barHeight: 36)))
    }

    @Test func roundsAndClampsBarHeight() {
        #expect(UIMessage(body: setPreferences(height: 36.6)) == .setPreferences(Preferences(hideHiddenApps: true, barHeight: 37)))
        #expect(UIMessage(body: setPreferences(height: 5)) == .setPreferences(Preferences(hideHiddenApps: true, barHeight: 28)))
        #expect(UIMessage(body: setPreferences(height: 999)) == .setPreferences(Preferences(hideHiddenApps: true, barHeight: 64)))
    }

    @Test func parsesScreenSpace() {
        #expect(UIMessage(body: setPreferences(screenSpace: "moveWindows"))
            == .setPreferences(Preferences(hideHiddenApps: true, screenSpace: .moveWindows)))
    }

    @Test func parsesResizeSettings() {
        #expect(UIMessage(body: ["type": "resizeSettings", "height": 412]) == .resizeSettings(height: 412))
        #expect(UIMessage(body: ["type": "resizeSettings"]) == nil)
    }

    @Test func rejectsMalformedMessages() {
        #expect(UIMessage(body: "ready") == nil)
        #expect(UIMessage(body: ["kind": "ready"]) == nil)
        #expect(UIMessage(body: ["type": "unknown"]) == nil)
        #expect(UIMessage(body: ["type": "activate"]) == nil)
        #expect(UIMessage(body: ["type": "activate", "bundleId": 42]) == nil)
        #expect(UIMessage(body: ["type": "setOrder", "order": "a,b"]) == nil)
        #expect(UIMessage(body: ["type": "setCollapsed"]) == nil)
        #expect(UIMessage(body: ["type": "setCollapsed", "collapsed": "yes"]) == nil)
        #expect(UIMessage(body: ["type": "setPreferences"]) == nil)
        #expect(UIMessage(body: ["type": "setPreferences", "preferences": ["hideHiddenApps": true]]) == nil)
        #expect(UIMessage(body: setPreferences(height: "36")) == nil)
        #expect(UIMessage(body: setPreferences(height: Double.nan)) == nil)
        #expect(UIMessage(body: setPreferences(screenSpace: "somethingElse")) == nil)
        #expect(UIMessage(body: setPreferences(screenSpace: 1)) == nil)
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
        let msg = try payload(NativeMessage.stateScript(apps: [entry], collapsed: true))
        #expect(msg["type"] as? String == "state")
        #expect(msg["collapsed"] as? Bool == true)
        let apps = try #require(msg["apps"] as? [[String: Any]])
        #expect(apps.count == 1)
        #expect(apps[0]["bundleId"] as? String == "com.apple.Notes")
        #expect(apps[0]["name"] as? String == "Notes")
        #expect(apps[0]["icon"] as? String == "data:image/png;base64,AA==")
        #expect(apps[0]["active"] as? Bool == true)
    }

    @Test func settingsHaveTheShapeTheUIExpects() throws {
        let script = NativeMessage.settingsScript(
            preferences: Preferences(hideHiddenApps: true, hideAppsWithoutWindows: false, barHeight: 36,
                                     screenSpace: .moveWindows),
            accessibilityTrusted: false, dockHeight: 36)
        let msg = try payload(script)
        #expect(msg["type"] as? String == "settings")
        #expect(msg["accessibilityTrusted"] as? Bool == false)
        #expect(msg["dockHeight"] as? Int == 36)
        #expect(msg["barHeightMin"] as? Int == 28)
        #expect(msg["barHeightMax"] as? Int == 64)
        let prefs = try #require(msg["preferences"] as? [String: Any])
        #expect(prefs["hideHiddenApps"] as? Bool == true)
        #expect(prefs["hideAppsWithoutWindows"] as? Bool == false)
        #expect(prefs["barHeight"] as? Int == 36)
        #expect(prefs["screenSpace"] as? String == "moveWindows")
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

    @Test func collapsedBarIsAThinStripInTheBottomRightCorner() {
        let frame = BarLayout.frame(screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), height: 36, collapsed: true)
        #expect(frame == CGRect(x: 1920 - BarLayout.collapsedWidth, y: 0, width: BarLayout.collapsedWidth, height: 36))
    }

    @Test func collapsedBarFollowsAnOffsetScreen() {
        let frame = BarLayout.frame(screen: CGRect(x: -2560, y: -200, width: 2560, height: 1440), height: 40, collapsed: true)
        #expect(frame.maxX == 0)
        #expect(frame.minY == -200)
        #expect(frame.width == BarLayout.collapsedWidth)
    }

    @Test func measuresTheDockAtTheBottom() {
        // Values from a real 1920x1080 display with a 16pt Dock and a 30pt menu bar.
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        #expect(BarLayout.dockHeight(screen: screen, visible: CGRect(x: 0, y: 36, width: 1920, height: 1014)) == 36)
    }

    @Test func noDockMeansZero() {
        // Dock hidden, on a side edge, or on another display.
        let screen = CGRect(x: 0, y: 0, width: 1496, height: 967)
        #expect(BarLayout.dockHeight(screen: screen, visible: CGRect(x: 0, y: 0, width: 1496, height: 939.5)) == 0)
        #expect(BarLayout.dockHeight(screen: screen, visible: CGRect(x: 60, y: 0, width: 1436, height: 939.5)) == 0)
    }

    @Test func dockHeightUsesTheScreensOwnOrigin() {
        let screen = CGRect(x: -1496, y: -200, width: 1496, height: 967)
        #expect(BarLayout.dockHeight(screen: screen, visible: CGRect(x: -1496, y: -164, width: 1496, height: 903.5)) == 36)
    }
}
