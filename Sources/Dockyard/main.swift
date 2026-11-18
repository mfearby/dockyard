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

// MARK: - Window counting

/// Counts each app's open windows for the "hide apps without windows" preference.
/// Uses Accessibility when permitted (includes minimised windows); otherwise falls back to on-screen windows.
struct WindowCounter {
    let trusted = AXIsProcessTrusted()
    private let onscreen: [Int32: Int]

    init() {
        if trusted {
            onscreen = [:]
        } else {
            let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] ?? []
            onscreen = WindowCounting.onscreenCounts(windowInfo: info)
        }
    }

    func count(for app: NSRunningApplication) -> Int {
        guard trusted else { return onscreen[app.processIdentifier] ?? 0 }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.25)  // don't let a hung app stall the bar
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            return 1  // can't tell, so keep the app on the bar
        }
        return windows.filter { window in
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
            return WindowCounting.isCountable(axSubrole: subrole as? String)
        }.count
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
            object: nil, queue: .main) { [weak self] _ in self?.positionPanel() }
    }

    /// Windows opening and closing don't post workspace notifications, so poll while that preference is on.
    private func updateWindowTimer() {
        if config.preferences.hideAppsWithoutWindows {
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

    private func runningApps() -> [NSRunningApplication] {
        let me = Bundle.main.bundleIdentifier
        let prefs = config.preferences
        let counter = prefs.hideAppsWithoutWindows ? WindowCounter() : nil
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            let isRegular = app.activationPolicy == .regular
            // Only count windows where the answer matters; Accessibility calls aren't free.
            let windowCount = (counter != nil && isRegular && !app.isHidden) ? counter?.count(for: app) : nil
            let snapshot = AppSnapshot(bundleId: app.bundleIdentifier, isRegular: isRegular,
                                       isTerminated: app.isTerminated, isHidden: app.isHidden,
                                       windowCount: windowCount)
            return AppFilter.shouldShow(snapshot, preferences: prefs, ownBundleId: me)
        }
        return AppOrdering.sorted(apps, by: config.order) { $0.bundleIdentifier! }
    }

    /// Sends the app list to the bar. Skips the send when nothing changed, since the window timer calls this every second.
    private func pushState(force: Bool = false) {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let apps = runningApps().map { app in
            let id = app.bundleIdentifier!
            return AppEntry(bundleId: id, name: app.localizedName ?? id,
                            icon: iconDataURL(for: app, id: id), active: id == front)
        }
        guard force || apps != lastSent else { return }
        lastSent = apps
        webView.evaluateJavaScript(NativeMessage.stateScript(apps: apps, collapsed: config.collapsed), completionHandler: nil)
    }

    // MARK: Options window

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = makeWebView(WKWebView.self)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 330),
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
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                if app.isHidden { app.unhide() }
                app.activate(options: [.activateAllWindows])
            }
        case .setOrder(let order):
            config.order = AppOrdering.merged(newOrder: order, into: config.order)
            try? store.save(config)
            pushState(force: true)
        case .setCollapsed(let collapsed):
            config.collapsed = collapsed
            try? store.save(config)
            positionPanel()
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
            pushState()
            sendSettings()
        case .requestAccessibility:
            // Adds Dockyard to the Accessibility list and shows the system prompt.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
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
