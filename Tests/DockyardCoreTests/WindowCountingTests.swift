import CoreGraphics
import DockyardCore
import Foundation
import Testing

struct WindowCountingTests {
    private func window(pid: Int32, layer: Int = 0, onscreen: Bool = true, alpha: Double = 1,
                        width: Double = 800, height: Double = 600) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowIsOnscreen as String: NSNumber(value: onscreen),
            kCGWindowAlpha as String: NSNumber(value: alpha),
            kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": width, "Height": height],
        ]
    }

    @Test func countsNormalOnscreenWindowsPerApp() {
        let counts = WindowCounting.onscreenCounts(windowInfo: [window(pid: 1), window(pid: 1), window(pid: 2)])
        #expect(counts == [1: 2, 2: 1])
    }

    @Test func ignoresMenuBarStripsAndTinyHelperWindows() {
        // Shapes seen on a real Mac: per-app menu bar strips and 1x1 / 64x64 helpers.
        let info = [window(pid: 1, width: 1920, height: 30), window(pid: 1, width: 1, height: 1),
                    window(pid: 1, width: 1496, height: 28), window(pid: 1, width: 40, height: 40)]
        #expect(WindowCounting.onscreenCounts(windowInfo: info).isEmpty)
    }

    @Test func ignoresOffscreenTransparentAndNonNormalLayerWindows() {
        let info = [window(pid: 1, onscreen: false), window(pid: 1, alpha: 0), window(pid: 1, layer: 25)]
        #expect(WindowCounting.onscreenCounts(windowInfo: info).isEmpty)
    }

    @Test func skipsEntriesWithMissingFields() {
        var broken = window(pid: 1)
        broken.removeValue(forKey: kCGWindowBounds as String)
        #expect(WindowCounting.onscreenCounts(windowInfo: [broken, [:]]).isEmpty)
    }

    @Test func countsStandardWindowsAndDialogsOnly() {
        #expect(WindowCounting.isCountable(axSubrole: "AXStandardWindow"))
        #expect(WindowCounting.isCountable(axSubrole: "AXDialog"))
        #expect(!WindowCounting.isCountable(axSubrole: "AXFloatingWindow"))
        #expect(!WindowCounting.isCountable(axSubrole: "AXSystemDialog"))
        #expect(!WindowCounting.isCountable(axSubrole: nil))
    }
}
