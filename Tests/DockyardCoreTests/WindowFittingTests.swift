import CoreGraphics
import DockyardCore
import Testing

struct WindowFittingTests {
    /// A 1920x1080 primary display with a 30pt menu bar and a 40pt taskbar, in Accessibility coordinates.
    private let area = WindowFitting.Area(top: 30, barTop: 1040, minX: 0, maxX: 1920)

    private func fit(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, resizable: Bool = true) -> CGRect? {
        WindowFitting.fitted(CGRect(x: x, y: y, width: w, height: h), in: area, resizable: resizable)
    }

    @Test func buildsTheAreaFromAppKitFrames() {
        // AppKit: origin bottom-left, y up. Dock hidden, so only the menu bar is taken from the visible frame.
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1050)
        #expect(WindowFitting.area(screen: screen, visible: visible, barHeight: 40) == area)
    }

    @Test func areaIgnoresADockOnTheSide() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let visible = CGRect(x: 60, y: 0, width: 1860, height: 1050)
        let result = WindowFitting.area(screen: screen, visible: visible, barHeight: 40)
        #expect(result.minX == 0 && result.maxX == 1920)
    }

    @Test func leavesWindowsAboveTheBarAlone() {
        #expect(fit(100, 100, 800, 600) == nil)
        #expect(fit(100, 440, 800, 600) == nil)  // ends exactly at the bar
    }

    @Test func shrinksAMaximisedWindow() {
        // What zoom or Fill produces when the Dock isn't reserving space.
        #expect(fit(0, 30, 1920, 1050) == CGRect(x: 0, y: 30, width: 1920, height: 1010))
    }

    @Test func movesASmallWindowUpWithoutResizing() {
        #expect(fit(200, 700, 800, 400) == CGRect(x: 200, y: 640, width: 800, height: 400))
        // Even a tall one, as long as there's room above it.
        #expect(fit(200, 100, 800, 1000) == CGRect(x: 200, y: 40, width: 800, height: 1000))
    }

    @Test func movesToTheMenuBarThenShrinksWhenThereIsNoRoom() {
        #expect(fit(200, 100, 800, 1050) == CGRect(x: 200, y: 30, width: 800, height: 1010))
    }

    @Test func fixedSizeWindowsOnlyMove() {
        #expect(fit(200, 100, 800, 1050, resizable: false) == CGRect(x: 200, y: 30, width: 800, height: 1050))
        // Already as high as it can go: nothing more to do, which also stops repeated attempts.
        #expect(fit(200, 30, 800, 1050, resizable: false) == nil)
    }

    @Test func neverPushesAWindowDown() {
        // A window that starts above the menu bar keeps its top edge and only shrinks.
        #expect(fit(200, 10, 800, 1070) == CGRect(x: 200, y: 10, width: 800, height: 1030))
    }

    @Test func leavesWindowsParkedBehindTheBar() {
        // Dragged down on purpose so only the title bar peeks out, or entirely off the bottom.
        #expect(fit(200, 1040, 800, 600) == nil)
        #expect(fit(200, 1060, 800, 600) == nil)
    }

    @Test func leavesWindowsOnOtherDisplays() {
        #expect(fit(1920, 500, 800, 800) == nil)   // display to the right
        #expect(fit(-1496, 500, 800, 800) == nil)  // display to the left
    }

    @Test func fitsAWindowThatOnlyPartlyOverlapsTheBarsDisplay() {
        #expect(fit(1500, 700, 800, 400) == CGRect(x: 1500, y: 640, width: 800, height: 400))
    }

    @Test func ignoresSubPointOverlaps() {
        #expect(fit(0, 30, 1920, 1010.4) == nil)
    }
}
