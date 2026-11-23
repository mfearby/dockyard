import AppKit
import ApplicationServices
import DockyardCore
import UniformTypeIdentifiers
import WebKit

// MARK: - Window classes

/// Borderless panel that never takes focus from the app you're working in.
final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on the bar register as a click, not just a focus request, and replaces WebKit's
/// right-click menu (Reload, Inspect Element) with Dockyard's own.
final class BarWebView: WKWebView {
    /// Called with the x position (points from the bar's left edge) of a right-click or Control-click.
    var onRightClick: ((CGFloat) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // WebKit doesn't pass these on to the page's script here, so they're handled natively. Not calling super
    // also stops WebKit's own menu.
    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(convert(event.locationInWindow, from: nil).x)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onRightClick?(convert(event.locationInWindow, from: nil).x)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.removeAllItems()  // in case WebKit opens its menu another way
    }
}

/// A web view without WebKit's right-click menu, for the Options window.
final class QuietWebView: WKWebView {
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.removeAllItems()
    }
}

// MARK: - Windows via Accessibility

/// Lets an AXUIElement be used as a dictionary key or in WindowRegistry. Equality is Accessibility's own
/// (same window), not object identity: each query returns a new AXUIElement for the same window.
struct WindowKey: Hashable {
    let element: AXUIElement
    static func == (a: WindowKey, b: WindowKey) -> Bool { CFEqual(a.element, b.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

/// One of an app's user-facing windows.
struct WindowInfo {
    let key: WindowKey
    let title: String?
}

enum AXWindows {
    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    /// The app's standard windows and dialogs, including minimised ones. Only windows on the current Space
    /// are reported by Accessibility. Returns nil if the app doesn't answer.
    static func list(pid: pid_t) -> [WindowInfo]? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)  // don't let a hung app stall the bar
        guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        return windows
            .filter { WindowCounting.isCountable(axSubrole: attribute($0, kAXSubroleAttribute) as? String) }
            .map { WindowInfo(key: WindowKey(element: $0), title: attribute($0, kAXTitleAttribute) as? String) }
    }

    /// Badge text by bundle ID for running apps, read from the Dock's items. Empty without Accessibility,
    /// or if the Dock doesn't answer.
    static func dockBadges() -> [String: String] {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return [:] }
        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(dockElement, 0.25)
        var items: [DockBadges.Item] = []
        for list in attribute(dockElement, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            for item in attribute(list, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                guard let label = attribute(item, "AXStatusLabel") as? String,
                      let url = attribute(item, kAXURLAttribute) as? URL else { continue }
                items.append(DockBadges.Item(appPath: url.path, label: label))
            }
        }
        var apps: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let path = app.bundleURL?.path, let id = app.bundleIdentifier { apps[path] = id }
        }
        return DockBadges.match(items, apps: apps)
    }

    static func focused(pid: pid_t) -> WindowKey? {
        let app = AXUIElementCreateApplication(pid)
        guard let value = attribute(app, kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return WindowKey(element: value as! AXUIElement)
    }

    /// Brings one window to the front, un-minimising it if needed, then activates its app.
    static func raise(_ window: AXUIElement, of app: NSRunningApplication) {
        if app.isHidden { app.unhide() }
        if attribute(window, kAXMinimizedAttribute) as? Bool == true {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        // Without .activateAllWindows, so only the raised window comes forward.
        app.activate(options: [])
    }

    // MARK: Window actions (taskbar right-click menu)

    /// The window an app button's menu acts on: the app's main window, else its focused one, else its first.
    static func primaryWindow(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        for name in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            if let value = attribute(app, name), CFGetTypeID(value) == AXUIElementGetTypeID() {
                return (value as! AXUIElement)
            }
        }
        return list(pid: pid)?.first?.key.element
    }

    static func isMinimised(_ window: AXUIElement) -> Bool {
        attribute(window, kAXMinimizedAttribute) as? Bool == true
    }

    static func setMinimised(_ window: AXUIElement, _ minimised: Bool) {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString,
                                     minimised ? kCFBooleanTrue : kCFBooleanFalse)
    }

    static func canResize(_ window: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable)
        return settable.boolValue
    }

    /// The window's close button, if it has one that's enabled.
    static func closeButton(_ window: AXUIElement) -> AXUIElement? {
        guard let value = attribute(window, kAXCloseButtonAttribute), CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let button = value as! AXUIElement
        return attribute(button, kAXEnabledAttribute) as? Bool == false ? nil : button
    }

    /// Clicks the close button, so the app can still ask to save changes, as when the user clicks it.
    static func close(_ window: AXUIElement) {
        if let button = closeButton(window) { AXUIElementPerformAction(button, kAXPressAction as CFString) }
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let position = attribute(window, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(window, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    static func setFrame(_ window: AXUIElement, _ frame: CGRect) {
        var origin = frame.origin
        var size = frame.size
        // Move first, then size, then move again: some apps clamp the size to the screen the window is on.
        if let value = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
        if let value = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
    }
}

/// What a taskbar button's right-click menu acts on.
final class MenuTarget: NSObject {
    let app: NSRunningApplication
    let window: AXUIElement?

    init(app: NSRunningApplication, window: AXUIElement?) {
        self.app = app
        self.window = window
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, WKScriptMessageHandler {
    private var panel: BarPanel!
    private var webView: BarWebView!
    private var tooltips: TooltipController!
    private var settingsWindow: NSWindow?
    private var settingsWebView: WKWebView?
    /// The app that was frontmost before Options opened, so focus can go back to it on close.
    private var previousApp: NSRunningApplication?
    private var webDir: URL?
    private let store = ConfigStore()
    private lazy var config = store.load()
    private var iconCache: [String: String] = [:]
    private var lastSent: [AppEntry]?
    private var quickLaunchItems: [AppSummary] = []
    /// Notices apps appearing (including ones still starting) and quitting, without waiting for the window timer.
    private var runningAppsObservation: NSKeyValueObservation?
    private var loadingRefreshScheduled = false
    private let launchTracker = LaunchTracker()
    /// The button whose window menu last closed, and when. A click on that button straight after the menu closes
    /// is the click that closed it, so it shouldn't reopen it.
    private var windowMenuClosed: (buttonID: String, time: Date)?
    private var windowMenuButton: String?
    private var windowTimer: Timer?
    private lazy var windowManager = WindowManager { [weak self] in self?.fittingArea() }
    private let windowRegistry = WindowRegistry<WindowKey>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        webDir = findWebDir()
        webView = makeWebView(BarWebView.self)

        panel = BarPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = true
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.contentView = webView
        tooltips = TooltipController(view: webView)
        webView.onRightClick = { [weak self] x in self?.showContextMenu(atBarX: x) }
        positionPanel()
        panel.orderFrontRegardless()

        refreshQuickLaunch()
        load("index.html", into: webView)
        observe()
        updateWindowTimer()
        updateWindowManager()
    }

    // MARK: Layout

    /// The primary display (the one with the menu bar in System Settings > Displays > Arrange).
    /// Not `NSScreen.main`: with "Displays have separate Spaces" on, that follows whichever screen is active,
    /// which moved the bar to another display whenever the Dock did.
    private var primaryScreen: NSScreen? { NSScreen.screens.first }

    private func positionPanel() {
        guard let screen = primaryScreen else { return }
        let height = CGFloat(config.preferences.barHeight)
        panel.setFrame(BarLayout.frame(screen: screen.frame, height: height, collapsed: config.collapsed), display: true)
    }

    // MARK: Window management

    /// Where other apps' windows must stay, or nil when Dockyard shouldn't move them:
    /// in "cover the Dock" mode, or while the bar is retracted and isn't covering anything.
    private func fittingArea() -> WindowFitting.Area? {
        guard config.preferences.screenSpace == .moveWindows, !config.collapsed, let screen = primaryScreen else { return nil }
        return WindowFitting.area(screen: screen.frame, visible: screen.visibleFrame,
                                  barHeight: CGFloat(config.preferences.barHeight))
    }

    /// Starts or stops window management to match the current settings, then refits existing windows,
    /// since the bar may have changed height or come back from being retracted.
    private func updateWindowManager() {
        if config.preferences.screenSpace == .moveWindows && AXIsProcessTrusted() {
            if windowManager.isRunning { windowManager.fitAll() } else { windowManager.start() }
        } else {
            windowManager.stop()
        }
    }

    // MARK: Web content

    private func makeWebView<T: WKWebView>(_ type: T.Type) -> T {
        let controller = WKUserContentController()
        controller.add(self, name: "native")
        let cfg = WKWebViewConfiguration()
        cfg.userContentController = controller
        let view = T(frame: .zero, configuration: cfg)
        view.isInspectable = true  // Safari > Develop > [your Mac] > Dockyard
        return view
    }

    private func findWebDir() -> URL? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let env = ProcessInfo.processInfo.environment["DOCKYARD_WEB_DIR"] { candidates.append(env) }
        if let res = Bundle.main.resourcePath { candidates.append(res + "/web") }
        candidates.append(fm.currentDirectoryPath + "/web/dist")
        return candidates.first { fm.fileExists(atPath: $0 + "/index.html") }.map { URL(fileURLWithPath: $0) }
    }

    private func load(_ page: String, into view: WKWebView) {
        guard let dir = webDir else {
            view.loadHTMLString(
                "<body style='font:13px sans-serif'>web/dist not found. Run: cd web &amp;&amp; npm run build</body>",
                baseURL: nil)
            return
        }
        view.loadFileURL(dir.appendingPathComponent(page), allowingReadAccessTo: dir)
    }

    // MARK: Running apps

    private func observe() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.pushState()
            }
        }
        runningAppsObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            DispatchQueue.main.async { self?.pushState() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.positionPanel()
                self?.updateWindowManager()
            }
    }

    /// Windows opening, closing, being renamed or switching focus within an app, and Dock badges changing,
    /// don't post workspace notifications, so poll while something depends on them.
    private func updateWindowTimer() {
        let prefs = config.preferences
        if prefs.hideAppsWithoutWindows || prefs.separateWindows || AXIsProcessTrusted() {
            guard windowTimer == nil else { return }
            windowTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.pushState()
            }
        } else {
            windowTimer?.invalidate()
            windowTimer = nil
        }
    }

    private func iconDataURL(for app: NSRunningApplication, id: String) -> String {
        iconDataURL(image: app.icon, id: id)
    }

    private func iconDataURL(image: NSImage?, id: String) -> String {
        if let cached = iconCache[id] { return cached }
        guard let icon = image else { return "" }
        let px = 64
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return "" }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return "" }
        let url = "data:image/png;base64," + png.base64EncodedString()
        iconCache[id] = url
        return url
    }

    /// Regular apps' windows, read once per refresh: every app's when a preference needs them, otherwise just
    /// those still starting (for the hourglass). Empty without Accessibility access.
    private func windowLists() -> [pid_t: [WindowInfo]] {
        let prefs = config.preferences
        guard AXIsProcessTrusted() else { return [:] }
        let needAll = prefs.hideAppsWithoutWindows || prefs.separateWindows
        var lists: [pid_t: [WindowInfo]] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isTerminated {
            guard needAll || launchTracker.inLaunchPhase(pid: app.processIdentifier, launchDate: app.launchDate)
            else { continue }
            if let list = AXWindows.list(pid: app.processIdentifier) { lists[app.processIdentifier] = list }
        }
        return lists
    }

    private func runningApps(windowLists: [pid_t: [WindowInfo]]) -> [NSRunningApplication] {
        let me = Bundle.main.bundleIdentifier
        let prefs = config.preferences
        // Without Accessibility, fall back to counting on-screen windows.
        var onscreen: [Int32: Int]?
        if prefs.hideAppsWithoutWindows && !AXIsProcessTrusted() {
            let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] ?? []
            onscreen = WindowCounting.onscreenCounts(windowInfo: info)
        }
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            let isRegular = app.activationPolicy == .regular
            var windowCount: Int?
            if prefs.hideAppsWithoutWindows && isRegular && !app.isHidden {
                if let onscreen {
                    windowCount = onscreen[app.processIdentifier] ?? 0
                } else {
                    // An app that didn't answer has no list; keep it on the bar rather than guess.
                    windowCount = windowLists[app.processIdentifier]?.count
                }
            }
            let snapshot = AppSnapshot(bundleId: app.bundleIdentifier, isRegular: isRegular,
                                       isTerminated: app.isTerminated, isHidden: app.isHidden,
                                       windowCount: windowCount, isLoading: isLoading(app, windowLists: windowLists))
            return AppFilter.shouldShow(snapshot, preferences: prefs, ownBundleId: me)
        }
        return AppOrdering.sorted(apps, by: config.order) { $0.bundleIdentifier! }
    }

    /// Still starting: not yet finished launching, or (when windows can be read) without its first window yet.
    private func isLoading(_ app: NSRunningApplication, windowLists: [pid_t: [WindowInfo]]) -> Bool {
        launchTracker.isLoading(pid: app.processIdentifier, finishedLaunching: app.isFinishedLaunching,
                                windowCount: windowLists[app.processIdentifier]?.count,
                                windowsVisible: AXIsProcessTrusted(), launchDate: app.launchDate)
    }

    /// The bar's buttons: one per app, or with "separate windows" on, one per window for apps that have any.
    private func entries() -> [AppEntry] {
        launchTracker.update(pids: Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier)))
        let lists = windowLists()
        let separate = config.preferences.separateWindows && AXIsProcessTrusted()
        let front = NSWorkspace.shared.frontmostApplication
        let badges = AXWindows.dockBadges()
        let apps = runningApps(windowLists: lists)
        windowRegistry.retain(pids: Set(apps.map(\.processIdentifier)))

        return apps.flatMap { app -> [AppEntry] in
            let id = app.bundleIdentifier!
            let name = app.localizedName ?? id
            let icon = iconDataURL(for: app, id: id)
            let isFront = app.processIdentifier == front?.processIdentifier
            let badge = badges[id]
            let loading = isLoading(app, windowLists: lists)
            guard separate, let list = lists[app.processIdentifier], !list.isEmpty else {
                return [AppEntry(bundleId: id, name: name, icon: icon, active: isFront, badge: badge, loading: loading)]
            }
            let titles = Dictionary(list.map { ($0.key, $0.title) }, uniquingKeysWith: { first, _ in first })
            let focused = isFront ? AXWindows.focused(pid: app.processIdentifier) : nil
            return windowRegistry.update(pid: app.processIdentifier, keys: list.map(\.key)).map { window in
                let title = titles[window.key] ?? nil
                // The tooltip repeats the full label, which the button may have cut short.
                return AppEntry(id: ButtonID.window(id, serial: window.serial), bundleId: id,
                                name: WindowLabel.name(title: title, appName: name),
                                icon: icon, active: window.key == focused, badge: badge, loading: loading)
            }
        }
    }

    /// Sends the buttons to the bar. Skips the send when nothing changed, since the window timer calls this every second.
    private func pushState(force: Bool = false) {
        let apps = entries()
        // Check again shortly while an app is starting, so its hourglass goes as soon as it has finished launching.
        if apps.contains(where: \.loading), !loadingRefreshScheduled {
            loadingRefreshScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.loadingRefreshScheduled = false
                self?.pushState()
            }
        }
        guard force || apps != lastSent else { return }
        lastSent = apps
        webView.evaluateJavaScript(
            NativeMessage.stateScript(apps: apps, collapsed: config.collapsed, theme: config.preferences.theme,
                                      quickLaunch: quickLaunchItems),
            completionHandler: nil)
    }

    private func activate(buttonID: String) {
        let parsed = ButtonID.parse(buttonID)
        if let serial = parsed.window, let window = windowRegistry.lookup(serial: serial),
           let app = NSRunningApplication(processIdentifier: window.pid) {
            AXWindows.raise(window.key.element, of: app)
        } else if let app = NSRunningApplication.runningApplications(withBundleIdentifier: parsed.bundleId).first {
            if let closed = windowMenuClosed, closed.buttonID == buttonID, Date().timeIntervalSince(closed.time) < 0.4 {
                windowMenuClosed = nil
                return
            }
            let isFront = app.processIdentifier == NSWorkspace.shared.frontmostApplication?.processIdentifier
            let windows = isFront && AXIsProcessTrusted() ? AXWindows.list(pid: app.processIdentifier) ?? [] : []
            if AppButtonClick.action(isFrontmost: isFront, windowCount: windows.count) == .showWindowMenu {
                showWindowMenu(app: app, windows: windows, buttonID: buttonID)
                return
            }
            if app.isHidden { app.unhide() }
            app.activate(options: [.activateAllWindows])
        }
        // Switching windows within the frontmost app posts no workspace notification, so refresh the highlight.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.pushState() }
    }

    // MARK: Options window

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = makeWebView(QuietWebView.self)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),  // the page resizes it to fit
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false)
            window.title = "Dockyard Options"
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.delegate = self
            window.center()
            load("settings.html", into: view)
            settingsWindow = window
            settingsWebView = view
        }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func sendSettings() {
        let screen = primaryScreen
        let dock = screen.map { BarLayout.dockHeight(screen: $0.frame, visible: $0.visibleFrame) } ?? 0
        // Match the window's title bar to the page. Only this window; menus keep following macOS's own setting.
        settingsWindow?.appearance = NSAppearance(named: config.preferences.theme == .dark ? .darkAqua : .aqua)
        let script = NativeMessage.settingsScript(
            preferences: config.preferences, accessibilityTrusted: AXIsProcessTrusted(), dockHeight: dock,
            excludedAppDetails: config.preferences.excludedApps.map(appSummary),
            quickLaunchDetails: config.preferences.quickLaunch.map(appSummary))
        settingsWebView?.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Refresh when Options comes back to the front, e.g. after granting Accessibility access in System Settings.
    func windowDidBecomeKey(_ notification: Notification) {
        sendSettings()
        updateWindowManager()
        updateWindowTimer()  // Accessibility may have just been granted, which turns on badge polling
    }

    // MARK: App lists (Options)

    /// Name and icon for an app that may not be running: from the running app if there is one, otherwise from
    /// its bundle on disk, otherwise just the bundle ID (e.g. an app that has since been deleted).
    private func appSummary(bundleId: String) -> AppSummary {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            return AppSummary(bundleId: bundleId, name: app.localizedName ?? bundleId,
                              icon: iconDataURL(for: app, id: bundleId))
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            var name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name.removeLast(4) }
            return AppSummary(bundleId: bundleId, name: name,
                              icon: iconDataURL(image: NSWorkspace.shared.icon(forFile: url.path), id: bundleId))
        }
        return AppSummary(bundleId: bundleId, name: bundleId, icon: "")
    }

    /// The Add… menu for one of the Options lists: running apps not already on it, then a file picker for
    /// anything else (such as an app that isn't running).
    private func showAppMenu(for list: AppList) {
        let already = Set(config.preferences.apps(in: list))
        let me = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        let apps = NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != me,
                      !already.contains(id) else { return false }
                return seen.insert(id).inserted
            }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }

        let menu = NSMenu()
        for app in apps {
            let item = NSMenuItem(title: app.localizedName ?? app.bundleIdentifier!,
                                  action: #selector(addAppFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [list.rawValue, app.bundleIdentifier!]
            if let icon = app.icon?.copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            menu.addItem(item)
        }
        if apps.isEmpty {
            let none = NSMenuItem(title: "No other apps are running", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        menu.addItem(.separator())
        let other = NSMenuItem(title: "Other Application…", action: #selector(chooseOtherApp(_:)), keyEquivalent: "")
        other.target = self
        other.representedObject = list.rawValue
        menu.addItem(other)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func addAppFromMenu(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2,
              let list = AppList(rawValue: pair[0]) else { return }
        add(pair[1], to: list)
    }

    @objc private func chooseOtherApp(_ sender: NSMenuItem) {
        guard let window = settingsWindow, let raw = sender.representedObject as? String,
              let list = AppList(rawValue: raw) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        panel.message = list == .quickLaunch
            ? "Choose an app to add to Quick Launch. System tools like Screenshot are in Utilities."
            : "Choose an app to never show in the taskbar."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
            self?.add(id, to: list)
        }
    }

    private func add(_ bundleId: String, to list: AppList) {
        guard bundleId != Bundle.main.bundleIdentifier, config.preferences.add(bundleId, to: list) else { return }
        try? store.save(config)
        refreshQuickLaunch()
        pushState(force: true)
        sendSettings()
    }

    // MARK: Quick Launch

    /// Rebuilds the Quick Launch icons from the preference. Done only when the list changes, because looking
    /// apps up on disk is too slow to repeat on every refresh. Apps that can no longer be found are left off the bar.
    private func refreshQuickLaunch() {
        quickLaunchItems = config.preferences.quickLaunch.map(appSummary).filter { !$0.icon.isEmpty }
    }

    /// Opens the app, or brings it to the front if it's already running.
    private func launch(bundleId: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error { NSLog("Dockyard: couldn't open %@: %@", bundleId, error.localizedDescription) }
        }
    }

    /// Sets the Options window's content height, keeping its top edge where it is.
    private func resizeSettings(to height: Double) {
        guard let window = settingsWindow else { return }
        let content = window.contentRect(forFrameRect: window.frame)
        let h = CGFloat(min(max(height, 120), 900))
        guard abs(content.height - h) >= 1 else { return }
        let newContent = NSRect(x: content.minX, y: content.maxY - h, width: content.width, height: h)
        window.setFrame(window.frameRect(forContentRect: newContent), display: true)
    }

    func windowWillClose(_ notification: Notification) {
        previousApp?.activate()
        previousApp = nil
    }

    // MARK: Messages from the UI

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let msg = UIMessage(body: message.body) else { return }
        switch msg {
        case .ready:
            pushState(force: true)
        case .activate(let id):
            activate(buttonID: id)
        case .setOrder(let ids):
            // Apps keep their saved positions; window order within an app lasts while its windows are open.
            config.order = AppOrdering.merged(newOrder: AppOrdering.bundleOrder(fromButtonIDs: ids), into: config.order)
            windowRegistry.reorder(serials: ids.compactMap { ButtonID.parse($0).window })
            try? store.save(config)
            pushState(force: true)
        case .launch(let bundleId):
            launch(bundleId: bundleId)
        case .setCollapsed(let collapsed):
            config.collapsed = collapsed
            try? store.save(config)
            positionPanel()
            updateWindowManager()
            pushState(force: true)
        case .setTooltips(let targets):
            tooltips.setTargets(targets)
        case .menu:
            showMenu()
        case .getSettings:
            sendSettings()
        case .setPreferences(let prefs):
            config.preferences = prefs
            try? store.save(config)
            refreshQuickLaunch()
            positionPanel()
            updateWindowTimer()
            updateWindowManager()
            pushState(force: true)  // the theme may have changed even if the buttons haven't
            sendSettings()
        case .requestAccessibility:
            // Adds Dockyard to the Accessibility list and shows the system prompt.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .chooseApp(let list):
            showAppMenu(for: list)
        case .resizeSettings(let height):
            resizeSettings(to: height)
        case .closeSettings:
            settingsWindow?.close()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let options = NSMenuItem(title: "Options…", action: #selector(openSettings), keyEquivalent: "")
        options.target = self
        menu.addItem(options)
        menu.addItem(.separator())

        // The same places the Dock offers: the Downloads stack, the Bin and Finder.
        let fm = FileManager.default
        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
        let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder")
        addMenuItem(to: menu, title: "Downloads", action: #selector(openDownloads),
                    icon: downloads.map { NSWorkspace.shared.icon(forFile: $0.path) })
        addMenuItem(to: menu, title: "Bin", action: #selector(openBin), icon: NSImage(named: NSImage.trashEmptyName))
        addMenuItem(to: menu, title: "Finder", action: #selector(openFinder),
                    icon: finder.map { NSWorkspace.shared.icon(forFile: $0.path) })
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Dockyard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: Window menu (app buttons, with windows grouped)

    /// Lists the app's windows in a menu just above its button. Choosing one brings it to the front; Escape or a
    /// click anywhere else (including on the button again) closes the menu.
    private func showWindowMenu(app: NSRunningApplication, windows: [WindowInfo], buttonID: String) {
        // Keep a stable order (first seen), rather than Accessibility's front-to-back order.
        let ordered = windowRegistry.update(pid: app.processIdentifier, keys: windows.map(\.key))
        let titles = Dictionary(windows.map { ($0.key, $0.title) }, uniquingKeysWith: { first, _ in first })
        let focused = AXWindows.focused(pid: app.processIdentifier)
        let name = app.localizedName ?? app.bundleIdentifier ?? ""

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        for window in ordered {
            let item = NSMenuItem(title: WindowLabel.menuTitle(title: titles[window.key] ?? nil, appName: name),
                                  action: #selector(raiseWindowFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = MenuTarget(app: app, window: window.key.element)
            if window.key == focused { item.state = .on }
            menu.addItem(item)
        }

        // Screen coordinates; the point is the menu's top-left, so this puts its bottom edge on the bar's top
        // and its left edge in line with the button's.
        let left = tooltips.target(id: buttonID).map { panel.frame.minX + CGFloat($0.left) } ?? NSEvent.mouseLocation.x
        windowMenuButton = buttonID
        menu.popUp(positioning: nil, at: NSPoint(x: left, y: panel.frame.maxY + menu.size.height), in: nil)
    }

    @objc private func raiseWindowFromMenu(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? MenuTarget, let window = target.window else { return }
        AXWindows.raise(window, of: target.app)
        refreshSoon()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard let buttonID = windowMenuButton else { return }
        windowMenuButton = nil
        windowMenuClosed = (buttonID, Date())
    }

    // MARK: Taskbar button menu

    /// Right-click on the bar: a taskbar button's menu over a button, the hamburger menu anywhere else.
    private func showContextMenu(atBarX x: CGFloat) {
        if let id = tooltips.target(atX: x)?.id, ButtonID.isTaskButton(id) {
            showButtonMenu(buttonID: id)
        } else {
            showMenu()
        }
    }

    /// The right-click menu for a taskbar button. Window items act on that button's window, or for an app button,
    /// on the app's main window. Hiding is left to Command-H.
    private func showButtonMenu(buttonID: String) {
        let parsed = ButtonID.parse(buttonID)
        var target: MenuTarget?
        if let serial = parsed.window, let found = windowRegistry.lookup(serial: serial),
           let app = NSRunningApplication(processIdentifier: found.pid) {
            target = MenuTarget(app: app, window: found.key.element)
        } else if let app = NSRunningApplication.runningApplications(withBundleIdentifier: parsed.bundleId).first {
            target = MenuTarget(app: app, window: AXIsProcessTrusted() ? AXWindows.primaryWindow(pid: app.processIdentifier) : nil)
        }
        guard let target else { return }

        let menu = NSMenu()
        menu.autoenablesItems = false
        let window = target.window
        let minimised = window.map(AXWindows.isMinimised) ?? false
        addTargetItem(to: menu, title: minimised ? "Restore" : "Minimise",
                      action: #selector(toggleMinimiseFromMenu(_:)), target: target, enabled: window != nil)
        addTargetItem(to: menu, title: "Maximise", action: #selector(maximiseFromMenu(_:)), target: target,
                      enabled: window.map(AXWindows.canResize) ?? false)
        addTargetItem(to: menu, title: "Close Window", action: #selector(closeWindowFromMenu(_:)), target: target,
                      enabled: window.flatMap(AXWindows.closeButton) != nil)
        menu.addItem(.separator())
        let name = target.app.localizedName ?? parsed.bundleId
        addTargetItem(to: menu, title: "Quit \(name)", action: #selector(quitFromMenu(_:)), target: target, enabled: true)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func addTargetItem(to menu: NSMenu, title: String, action: Selector, target: MenuTarget, enabled: Bool) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = target
        item.isEnabled = enabled
        menu.addItem(item)
    }

    @objc private func toggleMinimiseFromMenu(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? MenuTarget, let window = target.window else { return }
        if AXWindows.isMinimised(window) {
            AXWindows.raise(window, of: target.app)
        } else {
            AXWindows.setMinimised(window, true)
        }
        refreshSoon()
    }

    /// Sizes the window to fill its screen's usable area (above the taskbar on the bar's screen), without
    /// switching to macOS full screen.
    @objc private func maximiseFromMenu(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? MenuTarget, let window = target.window,
              let primary = primaryScreen else { return }
        if AXWindows.isMinimised(window) { AXWindows.setMinimised(window, false) }
        let primaryHeight = primary.frame.height
        let screens = NSScreen.screens
        let index = AXWindows.frame(of: window).flatMap {
            WindowFitting.screenIndex(of: $0, screens: screens.map(\.frame), primaryHeight: primaryHeight)
        } ?? 0
        let screen = screens[index]
        let barHeight: CGFloat = (screen == primary && !config.collapsed) ? CGFloat(config.preferences.barHeight) : 0
        let frame = WindowFitting.maximisedFrame(screen: screen.frame, visible: screen.visibleFrame,
                                                 barHeight: barHeight, primaryHeight: primaryHeight)
        AXWindows.setFrame(window, frame)
        AXWindows.raise(window, of: target.app)
        refreshSoon()
    }

    @objc private func closeWindowFromMenu(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? MenuTarget, let window = target.window else { return }
        AXWindows.close(window)
        refreshSoon()
    }

    /// Asks the app to quit normally, so it can still prompt to save unsaved work.
    @objc private func quitFromMenu(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? MenuTarget else { return }
        target.app.terminate()
    }

    /// Window changes from the menu post no workspace notification, so refresh the bar shortly after.
    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.pushState() }
    }

    private func addMenuItem(to menu: NSMenu, title: String, action: Selector, icon: NSImage?) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let icon = icon?.copy() as? NSImage {
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
        }
        menu.addItem(item)
    }

    /// Opens the Downloads folder in Finder, as clicking it in the Dock does when it's shown as a folder.
    @objc private func openDownloads() {
        if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens the Bin in a Finder window, like the Dock's Bin icon.
    @objc private func openBin() {
        if let url = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: false) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Brings Finder to the front. Like clicking it in the Dock, this sends a "reopen" event, so Finder opens
    /// a new window if none are open.
    @objc private func openFinder() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
