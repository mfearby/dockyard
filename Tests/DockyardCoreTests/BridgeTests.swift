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
        #expect(UIMessage(body: ["type": "activate", "id": "com.apple.Notes"]) == .activate(id: "com.apple.Notes"))
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
        #expect(UIMessage(body: ["type": "chooseApp", "list": "excludedApps"]) == .chooseApp(.excludedApps))
        #expect(UIMessage(body: ["type": "chooseApp", "list": "quickLaunch"]) == .chooseApp(.quickLaunch))
        #expect(UIMessage(body: ["type": "chooseApp", "list": "favourites"]) == nil)
        #expect(UIMessage(body: ["type": "chooseApp"]) == nil)
    }

    @Test func parsesLaunch() {
        #expect(UIMessage(body: ["type": "launch", "bundleId": "com.apple.screenshot.launcher"])
            == .launch(bundleId: "com.apple.screenshot.launcher"))
        #expect(UIMessage(body: ["type": "launch"]) == nil)
        #expect(UIMessage(body: ["type": "closeSettings"]) == .closeSettings)
    }

    private func setPreferences(height: Any = 40, screenSpace: Any = "coverDock",
                                excludedApps: Any = [String](), quickLaunch: Any = [String](),
                                theme: Any = "light") -> [String: Any] {
        ["type": "setPreferences",
         "preferences": ["hideHiddenApps": true, "hideAppsWithoutWindows": false, "barHeight": height,
                         "screenSpace": screenSpace, "separateWindows": false, "excludedApps": excludedApps,
                         "quickLaunch": quickLaunch, "theme": theme]]
    }

    @Test func parsesQuickLaunch() {
        #expect(UIMessage(body: setPreferences(quickLaunch: ["com.apple.screenshot.launcher"]))
            == .setPreferences(Preferences(hideHiddenApps: true, quickLaunch: ["com.apple.screenshot.launcher"])))
        #expect(UIMessage(body: setPreferences(quickLaunch: "com.apple.screenshot.launcher")) == nil)
    }

    @Test func parsesTheme() {
        #expect(UIMessage(body: setPreferences(theme: "dark")) == .setPreferences(Preferences(hideHiddenApps: true, theme: .dark)))
        #expect(UIMessage(body: setPreferences(theme: "purple")) == nil)
    }

    @Test func parsesExcludedApps() {
        #expect(UIMessage(body: setPreferences(excludedApps: ["com.spotify.client"]))
            == .setPreferences(Preferences(hideHiddenApps: true, excludedApps: ["com.spotify.client"])))
        #expect(UIMessage(body: setPreferences(excludedApps: "com.spotify.client")) == nil)
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
                                                   "screenSpace": "coverDock",
                                                   "separateWindows": NSNumber(value: true),
                                                   "excludedApps": [String](),
                                                   "quickLaunch": [String](),
                                                   "theme": "light"]]
        #expect(UIMessage(body: body)
            == .setPreferences(Preferences(hideHiddenApps: false, hideAppsWithoutWindows: true, barHeight: 36,
                                           separateWindows: true)))
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
        #expect(UIMessage(body: ["type": "activate", "id": 42]) == nil)
        #expect(UIMessage(body: ["type": "activate", "bundleId": "com.apple.Notes"]) == nil)
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

struct ButtonIDTests {
    @Test func appButtonsUseTheBundleId() {
        #expect(ButtonID.app("com.apple.Notes") == "com.apple.Notes")
        #expect(ButtonID.parse("com.apple.Notes") == ("com.apple.Notes", nil))
    }

    @Test func windowButtonsRoundTrip() {
        let id = ButtonID.window("com.jetbrains.intellij", serial: 7)
        #expect(id == "com.jetbrains.intellij#7")
        #expect(ButtonID.parse(id) == ("com.jetbrains.intellij", 7))
    }

    @Test func tellsTaskButtonsFromTheBarsOtherElements() {
        #expect(ButtonID.isTaskButton("com.apple.Notes"))
        #expect(ButtonID.isTaskButton("com.jetbrains.intellij#3"))
        #expect(!ButtonID.isTaskButton("start"))
        #expect(!ButtonID.isTaskButton("toggle"))
        #expect(!ButtonID.isTaskButton("launch:com.apple.screenshot.launcher"))
        #expect(!ButtonID.isTaskButton(""))
    }

    @Test func malformedSerialIsTreatedAsAnAppButton() {
        #expect(ButtonID.parse("com.example#abc") == ("com.example#abc", nil))
    }
}

struct WindowLabelTests {
    @Test func usesTheWindowTitle() {
        #expect(WindowLabel.name(title: "dockyard \u{2013} main.swift", appName: "IntelliJ IDEA") == "dockyard \u{2013} main.swift")
    }

    @Test func menuTitlesAreShortenedWhenLong() {
        #expect(WindowLabel.menuTitle(title: "dockyard", appName: "IntelliJ IDEA") == "dockyard")
        #expect(WindowLabel.menuTitle(title: nil, appName: "Notes") == "Notes")
        let long = String(repeating: "a", count: 100)
        let short = WindowLabel.menuTitle(title: long, appName: "App", maxLength: 10)
        #expect(short == String(repeating: "a", count: 9) + "\u{2026}")
        #expect(short.count == 10)
    }

    @Test func untitledWindowsUseTheAppName() {
        #expect(WindowLabel.name(title: nil, appName: "Notes") == "Notes")
        #expect(WindowLabel.name(title: "   ", appName: "Notes") == "Notes")
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
        let msg = try payload(NativeMessage.stateScript(
            apps: [entry], collapsed: true, theme: .dark,
            quickLaunch: [AppSummary(bundleId: "com.apple.screenshot.launcher", name: "Screenshot", icon: "data:,")]))
        let quick = try #require(msg["quickLaunch"] as? [[String: Any]])
        #expect(quick.count == 1)
        #expect(quick[0]["bundleId"] as? String == "com.apple.screenshot.launcher")
        #expect(quick[0]["name"] as? String == "Screenshot")
        #expect(msg["type"] as? String == "state")
        #expect(msg["collapsed"] as? Bool == true)
        #expect(msg["theme"] as? String == "dark")
        let apps = try #require(msg["apps"] as? [[String: Any]])
        #expect(apps.count == 1)
        #expect(apps[0]["id"] as? String == "com.apple.Notes")
        #expect(apps[0]["bundleId"] as? String == "com.apple.Notes")
        #expect(apps[0]["title"] as? String == "Notes")
        #expect(apps[0]["badge"] == nil)  // omitted when there's no badge
        #expect(apps[0]["name"] as? String == "Notes")
        #expect(apps[0]["icon"] as? String == "data:image/png;base64,AA==")
        #expect(apps[0]["active"] as? Bool == true)
    }

    @Test func settingsHaveTheShapeTheUIExpects() throws {
        let script = NativeMessage.settingsScript(
            preferences: Preferences(hideHiddenApps: true, hideAppsWithoutWindows: false, barHeight: 36,
                                     screenSpace: .moveWindows, excludedApps: ["com.spotify.client"]),
            accessibilityTrusted: false, dockHeight: 36,
            excludedAppDetails: [AppSummary(bundleId: "com.spotify.client", name: "Spotify", icon: "data:,")],
            quickLaunchDetails: [AppSummary(bundleId: "com.apple.Notes", name: "Notes", icon: "data:,")])
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
        #expect(prefs["excludedApps"] as? [String] == ["com.spotify.client"])
        let quickDetails = try #require(msg["quickLaunchDetails"] as? [[String: Any]])
        #expect(quickDetails.first?["name"] as? String == "Notes")
        let details = try #require(msg["excludedAppDetails"] as? [[String: Any]])
        #expect(details.count == 1)
        #expect(details[0]["bundleId"] as? String == "com.spotify.client")
        #expect(details[0]["name"] as? String == "Spotify")
        #expect(details[0]["icon"] as? String == "data:,")
    }

    @Test func badgesAreSentWhenPresent() throws {
        let entry = AppEntry(bundleId: "com.microsoft.Outlook", name: "Outlook", icon: "", active: false, badge: "1")
        let apps = try #require(try payload(NativeMessage.stateScript(apps: [entry]))["apps"] as? [[String: Any]])
        #expect(apps[0]["badge"] as? String == "1")
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
