import AppKit
import WebKit

let barHeight: CGFloat = 40

// MARK: - Config (~/.config/dockyard/config.json)

struct Config: Codable {
    var order: [String] = []
}

enum ConfigStore {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/dockyard/config.json")

    static func load() -> Config {
        guard let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        return cfg
    }

    static func save(_ cfg: Config) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(cfg) { try? data.write(to: url, options: .atomic) }
    }
}

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
    private var config = ConfigStore.load()
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
        let f = screen.frame
        panel.setFrame(NSRect(x: f.minX, y: f.minY, width: f.width, height: barHeight), display: true)
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
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != me && !$0.isTerminated
        }
        let order = config.order
        return apps.enumerated().sorted { a, b in
            let ia = order.firstIndex(of: a.element.bundleIdentifier!) ?? Int.max
            let ib = order.firstIndex(of: b.element.bundleIdentifier!) ?? Int.max
            return ia != ib ? ia < ib : a.offset < b.offset
        }.map { $0.element }
    }

    private func pushState() {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let apps: [[String: Any]] = runningApps().map { app in
            let id = app.bundleIdentifier!
            return ["bundleId": id,
                    "name": app.localizedName ?? id,
                    "icon": iconDataURL(for: app, id: id),
                    "active": id == front]
        }
        send(["type": "state", "apps": apps])
    }

    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.onNative && window.onNative(\(json))", completionHandler: nil)
    }

    // MARK: Messages from the UI

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            pushState()
        case "activate":
            if let id = body["bundleId"] as? String,
               let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                if app.isHidden { app.unhide() }
                app.activate(options: [.activateAllWindows])
            }
        case "setOrder":
            if let order = body["order"] as? [String] {
                // Keep remembered positions of apps that aren't currently running.
                config.order = order + config.order.filter { !order.contains($0) }
                ConfigStore.save(config)
            }
        case "menu":
            let menu = NSMenu()
            menu.addItem(withTitle: "Quit Dockyard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        default:
            break
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
