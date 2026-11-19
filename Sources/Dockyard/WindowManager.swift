import AppKit
import ApplicationServices
import DockyardCore

/// Keeps other apps' windows from extending under the taskbar, using the Accessibility API.
///
/// Windows are fitted when they're created or resized: new windows, zoom, Fill, tiling, and resize drags
/// (once the mouse is released, so Dockyard never fights the pointer). Plain moves are left alone, so a
/// window can still be dragged partly behind the bar on purpose, as on Windows.
final class WindowManager {
    /// The area windows must stay within, or nil when fitting is off (e.g. while the bar is retracted).
    private let area: () -> WindowFitting.Area?

    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    /// Windows resized while the mouse button was down, fitted once it's released.
    private var deferred: [AXUIElement] = []
    private var mouseTimer: Timer?
    /// Recent fits, so a window that refuses a size (e.g. a minimum height) isn't retried in a loop.
    private var recentFits: [(window: AXUIElement, target: CGRect, time: Date)] = []
    private(set) var isRunning = false

    init(area: @escaping () -> WindowFitting.Area?) {
        self.area = area
    }

    func start() {
        guard !isRunning, AXIsProcessTrusted() else { return }
        isRunning = true
        // Applies to every Accessibility call from this process, so a hung app can't stall the bar.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)

        let nc = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.observe(app, retries: 5)
            },
            nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.unobserve(app.processIdentifier)
            },
        ]
        for app in NSWorkspace.shared.runningApplications { observe(app) }
        NSLog("Dockyard: window management on, watching %d apps", observers.count)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        workspaceTokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceTokens = []
        for pid in Array(observers.keys) { unobserve(pid) }
        mouseTimer?.invalidate()
        mouseTimer = nil
        deferred = []
        recentFits = []
        NSLog("Dockyard: window management off")
    }

    /// Fits every existing window, e.g. after the bar changes height or comes back from being retracted.
    func fitAll() {
        guard isRunning else { return }
        for pid in observers.keys {
            windows(of: AXUIElementCreateApplication(pid)).forEach(fit)
        }
    }

    // MARK: Observing apps

    private func observe(_ app: NSRunningApplication, retries: Int = 0) {
        let pid = app.processIdentifier
        guard isRunning, !app.isTerminated, app.activationPolicy == .regular,
              pid != ProcessInfo.processInfo.processIdentifier, observers[pid] == nil else { return }

        var created: AXObserver?
        guard AXObserverCreate(pid, axCallback, &created) == .success, let observer = created else { return }
        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString, refcon)
        guard result == .success || result == .notificationAlreadyRegistered else {
            // An app that has only just launched may not answer Accessibility requests yet.
            if retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.observe(app, retries: retries - 1)
                }
            }
            return
        }
        // Registered on the app as well as on each window; duplicate callbacks are harmless because fitting is idempotent.
        _ = AXObserverAddNotification(observer, element, kAXWindowResizedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer

        // Catch windows that opened before observing started, such as an app's first window at launch.
        for window in windows(of: element) {
            watch(window, with: observer)
            fit(window)
        }
    }

    private func unobserve(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private func watch(_ window: AXUIElement, with observer: AXObserver) {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        _ = AXObserverAddNotification(observer, window, kAXWindowResizedNotification as CFString, refcon)
    }

    fileprivate func handle(_ element: AXUIElement, notification: String) {
        guard isRunning else { return }
        if notification == kAXWindowCreatedNotification as String {
            var pid: pid_t = 0
            if AXUIElementGetPid(element, &pid) == .success, let observer = observers[pid] {
                watch(element, with: observer)
            }
        }
        fitOrDefer(element)
    }

    // MARK: Fitting

    private func fitOrDefer(_ window: AXUIElement) {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            fit(window)
            return
        }
        if !deferred.contains(where: { CFEqual($0, window) }) { deferred.append(window) }
        guard mouseTimer == nil else { return }
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self, NSEvent.pressedMouseButtons & 1 == 0 else { return }
            timer.invalidate()
            self.mouseTimer = nil
            let windows = self.deferred
            self.deferred = []
            windows.forEach(self.fit)
        }
    }

    private func fit(_ window: AXUIElement) {
        guard let area = area(),
              WindowCounting.isCountable(axSubrole: attribute(window, kAXSubroleAttribute) as? String),
              attribute(window, kAXMinimizedAttribute) as? Bool != true,
              attribute(window, "AXFullScreen") as? Bool != true,
              let frame = frame(of: window) else { return }

        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable)
        guard let target = WindowFitting.fitted(frame, in: area, resizable: settable.boolValue),
              !triedRecently(window, target) else { return }

        if target.origin != frame.origin {
            var origin = target.origin
            if let value = AXValueCreate(.cgPoint, &origin) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            }
        }
        if target.size != frame.size {
            var size = target.size
            if let value = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
            }
        }
    }

    private func triedRecently(_ window: AXUIElement, _ target: CGRect) -> Bool {
        let now = Date()
        recentFits.removeAll { now.timeIntervalSince($0.time) > 1 }
        if recentFits.contains(where: { $0.target == target && CFEqual($0.window, window) }) { return true }
        recentFits.append((window, target, now))
        return false
    }

    // MARK: Accessibility helpers

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private func windows(of app: AXUIElement) -> [AXUIElement] {
        attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        guard let position = attribute(window, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(window, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}

/// C callback for AXObserver; `refcon` is the WindowManager that registered the notification.
private let axCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let manager = Unmanaged<WindowManager>.fromOpaque(refcon).takeUnretainedValue()
    manager.handle(element, notification: notification as String)
}
