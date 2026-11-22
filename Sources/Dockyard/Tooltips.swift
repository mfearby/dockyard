import AppKit
import DockyardCore

/// Windows-style tooltips for the bar.
///
/// macOS only shows standard tooltips (including the web view's `title` ones) while the app is active, and
/// Dockyard never is: the bar is non-activating so clicks don't steal focus. So this tracks the pointer
/// itself with an always-active tracking area and draws the tooltip in its own small window above the bar.
final class TooltipController: NSResponder {
    /// Delay before the first tooltip appears, and how soon after one hides the next shows without a delay
    /// (moving along the bar), as on Windows.
    private let showDelay: TimeInterval = 0.5
    private let reshowWindow: TimeInterval = 0.5

    private weak var view: NSView?
    private var targets: [TooltipTarget] = []
    /// The target under the pointer, shown or waiting to be.
    private var hoveredID: String?
    /// Set by a click; no tooltip for this target until the pointer moves to another one.
    private var suppressedID: String?
    private var timer: Timer?
    private var lastHidden = Date.distantPast
    private var mouseMonitor: Any?

    private let panel: NSPanel
    private let label: NSTextField

    init(view: NSView) {
        self.view = view
        label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .black
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(srgbRed: 1, green: 1, blue: 0xE1 / 255.0, alpha: 1).cgColor
        content.layer?.borderColor = NSColor.black.cgColor
        content.layer?.borderWidth = 1
        content.addSubview(label)

        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)  // above the bar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.contentView = content
        super.init()

        view.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
        // Clicks on the bar reach this app even though it isn't active, so a local monitor sees them.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] event in
            self?.clicked()
            return event
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
    }

    /// The element at `x` (points from the bar's left edge), using the same positions as the tooltips.
    func target(atX x: CGFloat) -> TooltipTarget? {
        TooltipTarget.hit(Double(x), in: targets)
    }

    /// The element with this ID, e.g. to place a menu above a taskbar button.
    func target(id: String) -> TooltipTarget? {
        targets.first { $0.id == id }
    }

    func setTargets(_ targets: [TooltipTarget]) {
        self.targets = targets
        // The buttons changed under a still pointer: follow whatever is there now.
        if let window = view?.window, window.frame.contains(NSEvent.mouseLocation) {
            update(x: NSEvent.mouseLocation.x - window.frame.minX, force: true)
        } else {
            leave()
        }
    }

    // MARK: Tracking

    override func mouseMoved(with event: NSEvent) {
        update(x: event.locationInWindow.x)
    }

    override func mouseEntered(with event: NSEvent) {
        update(x: event.locationInWindow.x)
    }

    override func mouseExited(with event: NSEvent) {
        leave()
    }

    private func leave() {
        hoveredID = nil
        suppressedID = nil
        hide()
    }

    private func clicked() {
        suppressedID = hoveredID
        hide()
    }

    private func update(x: CGFloat, force: Bool = false) {
        let target = TooltipTarget.hit(Double(x), in: targets)
        if target?.id == hoveredID {
            // Same target after the buttons were refreshed: update the text (e.g. a window was renamed),
            // without restarting a pending delay.
            if force, panel.isVisible, let target { show(target) }
            return
        }
        hoveredID = target?.id
        if target?.id != suppressedID { suppressedID = nil }
        hide()
        guard let target, target.id != suppressedID else { return }

        if Date().timeIntervalSince(lastHidden) < reshowWindow {
            show(target)
        } else {
            timer = Timer.scheduledTimer(withTimeInterval: showDelay, repeats: false) { [weak self] _ in
                self?.show(target)
            }
        }
    }

    // MARK: Drawing

    private func show(_ target: TooltipTarget) {
        guard let bar = view?.window, let screen = bar.screen ?? NSScreen.screens.first else { return }
        label.stringValue = target.text
        label.sizeToFit()
        let maxTextWidth = min(600, screen.frame.width - 20)
        let textSize = CGSize(width: min(ceil(label.frame.width), maxTextWidth), height: ceil(label.frame.height))
        let size = CGSize(width: textSize.width + 8, height: textSize.height + 4)
        label.frame = CGRect(x: 4, y: 2, width: textSize.width, height: textSize.height)
        let frame = TooltipTarget.frame(size: size, targetLeft: bar.frame.minX + CGFloat(target.left),
                                        barTop: bar.frame.maxY, screen: screen.frame)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    private func hide() {
        timer?.invalidate()
        timer = nil
        if panel.isVisible {
            panel.orderOut(nil)
            lastHidden = Date()
        }
    }
}
