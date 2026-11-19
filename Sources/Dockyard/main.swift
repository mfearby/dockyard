import AppKit
import ApplicationServices
import DockyardCore
import WebKit

// MARK: - Window classes

/// Borderless panel that never takes focus from the app you're working in.
final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on the bar register as a click, not just a focus request.
final class BarWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler {
    private var panel: BarPanel!
    private var webView: BarWebView!
    private var settingsWindow: NSWindow?
    private var settingsWebView: WKWebView?
    /// The app that was frontmost before Options opened, so focus can go back to it on close.
    private var previousApp: NSRunningApplication?
    private var webDir: URL?
    private let store = ConfigStore()
    private lazy var config = store.load()
    private var iconCache: [String: String] = [:]
    private var lastSent: [AppEntry]?
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
        positionPanel()
        panel.orderFrontRegardless()

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
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.positionPanel()
                self?.updateWindowManager()
            }
    }

    /// Windows opening, closing, being renamed or switching focus within an app don't post workspace
    /// notifications, so poll while a preference depends on them.
    private func updateWindowTimer() {
        if config.preferences.hideAppsWithoutWindows || config.preferences.separateWindows {
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
        if let cached = iconCache[id] { return cached }
        guard let icon = app.icon else { return "" }
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

    /// Each regular app's windows, read once per refresh. Empty when no preference needs them or
    /// Accessibility isn't granted.
    private func windowLists() -> [pid_t: [WindowInfo]] {
        let prefs = config.preferences
        guard prefs.hideAppsWithoutWindows || prefs.separateWindows, AXIsProcessTrusted() else { return [:] }
        var lists: [pid_t: [WindowInfo]] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isTerminated {
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
                                       windowCount: windowCount)
            return AppFilter.shouldShow(snapshot, preferences: prefs, ownBundleId: me)
        }
        return AppOrdering.sorted(apps, by: config.order) { $0.bundleIdentifier! }
    }

    /// The bar's buttons: one per app, or with "separate windows" on, one per window for apps that have any.
    private func entries() -> [AppEntry] {
        let lists = windowLists()
        let separate = config.preferences.separateWindows && AXIsProcessTrusted()
        let front = NSWorkspace.shared.frontmostApplication
        let apps = runningApps(windowLists: lists)
        windowRegistry.retain(pids: Set(apps.map(\.processIdentifier)))

        return apps.flatMap { app -> [AppEntry] in
            let id = app.bundleIdentifier!
            let name = app.localizedName ?? id
            let icon = iconDataURL(for: app, id: id)
            let isFront = app.processIdentifier == front?.processIdentifier
            guard separate, let list = lists[app.processIdentifier], !list.isEmpty else {
                return [AppEntry(bundleId: id, name: name, icon: icon, active: isFront)]
            }
            let titles = Dictionary(list.map { ($0.key, $0.title) }, uniquingKeysWith: { first, _ in first })
            let focused = isFront ? AXWindows.focused(pid: app.processIdentifier) : nil
            return windowRegistry.update(pid: app.processIdentifier, keys: list.map(\.key)).map { window in
                let title = titles[window.key] ?? nil
                return AppEntry(id: ButtonID.window(id, serial: window.serial), bundleId: id,
                                name: WindowLabel.name(title: title, appName: name),
                                title: WindowLabel.tooltip(title: title, appName: name),
                                icon: icon, active: window.key == focused)
            }
        }
    }

    /// Sends the buttons to the bar. Skips the send when nothing changed, since the window timer calls this every second.
    private func pushState(force: Bool = false) {
        let apps = entries()
        guard force || apps != lastSent else { return }
        lastSent = apps
        webView.evaluateJavaScript(NativeMessage.stateScript(apps: apps, collapsed: config.collapsed), completionHandler: nil)
    }

    private func activate(buttonID: String) {
        let parsed = ButtonID.parse(buttonID)
        if let serial = parsed.window, let window = windowRegistry.lookup(serial: serial),
           let app = NSRunningApplication(processIdentifier: window.pid) {
            AXWindows.raise(window.key.element, of: app)
        } else if let app = NSRunningApplication.runningApplications(withBundleIdentifier: parsed.bundleId).first {
            if app.isHidden { app.unhide() }
            app.activate(options: [.activateAllWindows])
        }
        // Switching windows within the frontmost app posts no workspace notification, so refresh the highlight.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.pushState() }
    }

    // MARK: Options window

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = makeWebView(WKWebView.self)
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
        let script = NativeMessage.settingsScript(
            preferences: config.preferences, accessibilityTrusted: AXIsProcessTrusted(), dockHeight: dock)
        settingsWebView?.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Refresh when Options comes back to the front, e.g. after granting Accessibility access in System Settings.
    func windowDidBecomeKey(_ notification: Notification) {
        sendSettings()
        updateWindowManager()
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
        case .setCollapsed(let collapsed):
            config.collapsed = collapsed
            try? store.save(config)
            positionPanel()
            updateWindowManager()
            pushState(force: true)
        case .menu:
            showStartMenu()
        case .getSettings:
            sendSettings()
        case .setPreferences(let prefs):
            config.preferences = prefs
            try? store.save(config)
            positionPanel()
            updateWindowTimer()
            updateWindowManager()
            pushState()
            sendSettings()
        case .requestAccessibility:
            // Adds Dockyard to the Accessibility list and shows the system prompt.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .resizeSettings(let height):
            resizeSettings(to: height)
        case .closeSettings:
            settingsWindow?.close()
        }
    }

    private func showStartMenu() {
        let menu = NSMenu()
        let options = NSMenuItem(title: "Options…", action: #selector(openSettings), keyEquivalent: "")
        options.target = self
        menu.addItem(options)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Dockyard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
