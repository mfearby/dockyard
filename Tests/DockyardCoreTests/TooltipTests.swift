import CoreGraphics
import DockyardCore
import Foundation
import Testing

struct TooltipTests {
    private let targets = [
        TooltipTarget(id: "a", text: "Finder", left: 100, width: 160),
        TooltipTarget(id: "b", text: "IntelliJ IDEA \u{2013} dockyard", left: 262, width: 160),
        TooltipTarget(id: "hidden", text: "Gone", left: 424, width: 0),
        TooltipTarget(id: "blank", text: "", left: 500, width: 100),
    ]

    @Test func findsTheTargetUnderThePointer() {
        #expect(TooltipTarget.hit(100, in: targets)?.id == "a")
        #expect(TooltipTarget.hit(300, in: targets)?.id == "b")
    }

    @Test func gapsAndEdgesHitNothing() {
        #expect(TooltipTarget.hit(260, in: targets) == nil)  // the 2px gap between buttons
        #expect(TooltipTarget.hit(99, in: targets) == nil)
        #expect(TooltipTarget.hit(422, in: targets) == nil)  // right edge is exclusive
    }

    @Test func ignoresHiddenAndEmptyTargets() {
        #expect(TooltipTarget.hit(424, in: targets) == nil)
        #expect(TooltipTarget.hit(550, in: targets) == nil)
    }

    @Test func sitsJustAboveTheBarAlignedWithTheButton() {
        let frame = TooltipTarget.frame(size: CGSize(width: 120, height: 18), targetLeft: 500, barTop: 40,
                                        screen: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(frame == CGRect(x: 500, y: 42, width: 120, height: 18))
    }

    @Test func staysOnScreenNearTheRightEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = TooltipTarget.frame(size: CGSize(width: 300, height: 18), targetLeft: 1900, barTop: 40, screen: screen)
        #expect(frame.maxX == 1918)
    }

    @Test func parsesTheMessageAndSkipsBadEntries() {
        let body: [String: Any] = ["type": "setTooltips", "tooltips": [
            ["id": "a", "text": "Finder", "left": NSNumber(value: 100.5), "width": 160],
            ["id": "b", "text": "No position"],
            "not a dict",
        ]]
        #expect(UIMessage(body: body) == .setTooltips([TooltipTarget(id: "a", text: "Finder", left: 100.5, width: 160)]))
        #expect(UIMessage(body: ["type": "setTooltips"]) == nil)
    }
}
