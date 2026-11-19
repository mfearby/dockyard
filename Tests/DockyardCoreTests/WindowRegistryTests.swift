import DockyardCore
import Testing

struct WindowRegistryTests {
    private func keys(_ entries: [(key: String, serial: Int)]) -> [String] { entries.map(\.key) }

    @Test func firstSeenOrderIsKept() {
        let registry = WindowRegistry<String>()
        registry.update(pid: 1, keys: ["a", "b", "c"])
        // Accessibility lists windows front to back, so focusing "c" moves it first. The buttons shouldn't move.
        #expect(keys(registry.update(pid: 1, keys: ["c", "a", "b"])) == ["a", "b", "c"])
    }

    @Test func serialsAreStableAndUnique() {
        let registry = WindowRegistry<String>()
        let first = registry.update(pid: 1, keys: ["a", "b"])
        let again = registry.update(pid: 1, keys: ["b", "a"])
        let other = registry.update(pid: 2, keys: ["a"])
        #expect(first.map(\.serial) == again.map(\.serial))
        #expect(Set(first.map(\.serial) + other.map(\.serial)).count == 3)
    }

    @Test func newWindowsGoLastAndClosedOnesAreForgotten() {
        let registry = WindowRegistry<String>()
        let first = registry.update(pid: 1, keys: ["a", "b"])
        #expect(keys(registry.update(pid: 1, keys: ["d", "b"])) == ["b", "d"])
        let serialOfA = first[0].serial
        #expect(registry.lookup(serial: serialOfA) == nil)
    }

    @Test func lookupFindsTheWindowAndItsApp() throws {
        let registry = WindowRegistry<String>()
        registry.update(pid: 1, keys: ["a"])
        let serial = registry.update(pid: 2, keys: ["x"])[0].serial
        let found = try #require(registry.lookup(serial: serial))
        #expect(found.pid == 2 && found.key == "x")
    }

    @Test func reorderFollowsTheDraggedOrder() {
        let registry = WindowRegistry<String>()
        let s = registry.update(pid: 1, keys: ["a", "b", "c"]).map(\.serial)
        registry.reorder(serials: [s[2], s[0], s[1]])
        #expect(keys(registry.update(pid: 1, keys: ["a", "b", "c"])) == ["c", "a", "b"])
    }

    @Test func reorderKeepsUnlistedWindowsAfterListedOnes() {
        let registry = WindowRegistry<String>()
        let s = registry.update(pid: 1, keys: ["a", "b", "c"]).map(\.serial)
        registry.reorder(serials: [s[1]])
        #expect(keys(registry.update(pid: 1, keys: ["a", "b", "c"])) == ["b", "a", "c"])
    }

    @Test func retainForgetsQuitApps() {
        let registry = WindowRegistry<String>()
        let serial = registry.update(pid: 1, keys: ["a"])[0].serial
        registry.update(pid: 2, keys: ["b"])
        registry.retain(pids: [2])
        #expect(registry.lookup(serial: serial) == nil)
    }

    @Test func duplicateKeysAreListedOnce() {
        let registry = WindowRegistry<String>()
        #expect(keys(registry.update(pid: 1, keys: ["a", "a", "b"])) == ["a", "b"])
    }
}
