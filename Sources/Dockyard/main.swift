import AppKit
import DockyardCore
import WebKit

let barHeight: CGFloat = 40

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

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    private var panel: BarPanel!
    private var webView: BarWebView!
    private let store = ConfigStore()
    private lazy var config = store.load()
    private var iconCache: [String: String] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = WKUserContentController()
        controller.add(self, name: "native")
        let cfg = WKWebViewConfiguration()
        cfg.userContentController = controller

        webView = BarWebView(frame: .zero, configuration: cfg)
        webView.isInspectable = true  // Safari > Develop > [your Mac] > Dockyard

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

        loadWeb()
        observe()
    }

    // MARK: Layout

    private func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        panel.setFrame(BarLayout.frame(screen: screen.frame, height: barHeight), display: true)
    }

    // MARK: Web content

    private func loadWeb() {
        let fm = FileManager.default
        var candidates: [String] = []
        if let env = ProcessInfo.processInfo.environment["DOCKYARD_WEB_DIR"] { candidates.append(env) }
        if let res = Bundle.main.resourcePath { candidates.append(res + "/web") }
        candidates.append(fm.currentDirectoryPath + "/web/dist")

        for dir in candidates where fm.fileExists(atPath: dir + "/index.html") {
            let base = URL(fileURLWithPath: dir)
            webView.loadFileURL(base.appendingPathComponent("index.html"), allowingReadAccessTo: base)
            return
        }
        webView.loadHTMLString(
            "<body style='font:13px sans-serif'>web/dist not found. Run: cd web &amp;&amp; npm run build</body>",
            baseURL: nil)
    }

    // MARK: Running apps

    private func observe() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.pushState()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.positionPanel() }
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
        let apps = NSWorkspace.shared.runningApplications.filter {
            AppFilter.shouldShow(bundleId: $0.bundleIdentifier, isRegular: $0.activationPolicy == .regular,
                                 isTerminated: $0.isTerminated, ownBundleId: me)
        }
        return AppOrdering.sorted(apps, by: config.order) { $0.bundleIdentifier! }
    }

    private func pushState() {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let apps = runningApps().map { app in
            let id = app.bundleIdentifier!
            return AppEntry(bundleId: id, name: app.localizedName ?? id,
                            icon: iconDataURL(for: app, id: id), active: id == front)
        }
        webView.evaluateJavaScript(NativeMessage.stateScript(apps: apps), completionHandler: nil)
    }

    // MARK: Messages from the UI

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let msg = UIMessage(body: message.body) else { return }
        switch msg {
        case .ready:
            pushState()
        case .activate(let id):
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                if app.isHidden { app.unhide() }
                app.activate(options: [.activateAllWindows])
            }
        case .setOrder(let order):
            config.order = AppOrdering.merged(newOrder: order, into: config.order)
            try? store.save(config)
            pushState()
        case .menu:
            let menu = NSMenu()
            menu.addItem(withTitle: "Quit Dockyard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
