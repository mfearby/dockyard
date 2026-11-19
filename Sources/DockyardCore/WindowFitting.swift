import CoreGraphics

/// Decides where a window should go so it doesn't extend under the taskbar.
///
/// Everything here uses Accessibility coordinates: the origin is the top-left corner of the primary display
/// and y increases downwards, so a window's `maxY` is its bottom edge.
public enum WindowFitting {
    /// The part of the primary display that windows should stay within.
    public struct Area: Equatable {
        /// Bottom of the menu bar. Windows aren't moved above this.
        public var top: CGFloat
        /// Top edge of the taskbar. Windows should end at or above this.
        public var barTop: CGFloat
        /// Horizontal extent of the taskbar. Windows entirely outside it (e.g. on another display) are left alone.
        public var minX: CGFloat
        public var maxX: CGFloat

        public init(top: CGFloat, barTop: CGFloat, minX: CGFloat, maxX: CGFloat) {
            self.top = top
            self.barTop = barTop
            self.minX = minX
            self.maxX = maxX
        }
    }

    /// Builds the area from the primary display's AppKit frames (origin bottom-left, y up).
    public static func area(screen: CGRect, visible: CGRect, barHeight: CGFloat) -> Area {
        // AppKit y converts to Accessibility y as (primary display's maxY - y).
        Area(top: screen.maxY - visible.maxY,
             barTop: screen.height - barHeight,
             minX: screen.minX,
             maxX: screen.maxX)
    }

    /// Where `window` should move to, or nil if it can stay where it is.
    ///
    /// - A window that ends under the bar moves up if there's room above it, keeping its size.
    /// - Otherwise it moves up to the menu bar and, if `resizable`, shrinks to end at the bar.
    /// - A window whose top edge is already at or below the bar's top was most likely parked there on purpose,
    ///   so it's left alone, as are windows beside the bar on another display.
    public static func fitted(_ window: CGRect, in area: Area, resizable: Bool) -> CGRect? {
        let tolerance: CGFloat = 0.5
        guard window.maxY > area.barTop + tolerance,
              window.minY < area.barTop,
              window.maxX > area.minX, window.minX < area.maxX else { return nil }

        let overlap = window.maxY - area.barTop
        let result: CGRect
        if window.minY - overlap >= area.top {
            result = window.offsetBy(dx: 0, dy: -overlap)
        } else {
            // Never push a window down: one that already starts above the menu bar keeps its top edge.
            let top = min(window.minY, area.top)
            let height = resizable ? area.barTop - top : window.height
            result = CGRect(x: window.minX, y: top, width: window.width, height: height)
        }
        return result == window ? nil : result
    }
}
