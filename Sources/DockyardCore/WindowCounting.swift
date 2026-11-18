import CoreGraphics
import Foundation

/// Rules for deciding which of an app's windows count as real, user-facing windows.
public enum WindowCounting {
    /// Windows smaller than this are invisible helpers or per-app menu bar strips (about 30pt tall), not real windows.
    public static let minimumSize = CGSize(width: 50, height: 50)

    /// Accessibility subroles that represent windows a user would think of as open.
    public static func isCountable(axSubrole: String?) -> Bool {
        axSubrole == "AXStandardWindow" || axSubrole == "AXDialog"
    }

    /// Counts on-screen, normal-level windows per process from `CGWindowListCopyWindowInfo` output.
    /// Used when Accessibility access isn't granted. Minimised windows and windows on other Spaces aren't counted.
    public static func onscreenCounts(windowInfo: [[String: Any]]) -> [Int32: Int] {
        var counts: [Int32: Int] = [:]
        for window in windowInfo {
            guard let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
                  ((window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue,
                  width >= minimumSize.width, height >= minimumSize.height
            else { continue }
            counts[pid, default: 0] += 1
        }
        return counts
    }
}
