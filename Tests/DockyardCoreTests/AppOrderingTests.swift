import DockyardCore
import Testing

struct AppOrderingTests {
    private func sorted(_ ids: [String], by order: [String]) -> [String] {
        AppOrdering.sorted(ids, by: order) { $0 }
    }

    @Test func sortsBySavedOrder() {
        #expect(sorted(["c", "a", "b"], by: ["a", "b", "c"]) == ["a", "b", "c"])
    }

    @Test func unknownAppsGoLastInLaunchOrder() {
        #expect(sorted(["x", "b", "y", "a"], by: ["a", "b"]) == ["a", "b", "x", "y"])
    }

    @Test func emptySavedOrderKeepsLaunchOrder() {
        #expect(sorted(["c", "a", "b"], by: []) == ["c", "a", "b"])
    }

    @Test func savedAppsThatAreNotRunningAreIgnored() {
        #expect(sorted(["b", "a"], by: ["z", "a", "y", "b"]) == ["a", "b"])
    }

    @Test func duplicateSavedIdsUseFirstPosition() {
        #expect(sorted(["b", "a"], by: ["a", "b", "a"]) == ["a", "b"])
    }

    @Test func mergeKeepsNonRunningAppsAfterRunningOnes() {
        // Saved: a b c d. Only c and a are running and the user dragged c in front of a.
        #expect(AppOrdering.merged(newOrder: ["c", "a"], into: ["a", "b", "c", "d"]) == ["c", "a", "b", "d"])
    }

    @Test func mergeIntoEmptySavedOrder() {
        #expect(AppOrdering.merged(newOrder: ["b", "a"], into: []) == ["b", "a"])
    }
}

struct AppFilterTests {
    @Test func showsOrdinaryApps() {
        #expect(AppFilter.shouldShow(bundleId: "com.apple.Notes", isRegular: true, isTerminated: false, ownBundleId: "local.dockyard"))
    }

    @Test func hidesBackgroundAppsAndAgents() {
        #expect(!AppFilter.shouldShow(bundleId: "com.apple.Notes", isRegular: false, isTerminated: false, ownBundleId: nil))
    }

    @Test func hidesTerminatedApps() {
        #expect(!AppFilter.shouldShow(bundleId: "com.apple.Notes", isRegular: true, isTerminated: true, ownBundleId: nil))
    }

    @Test func hidesAppsWithoutBundleId() {
        #expect(!AppFilter.shouldShow(bundleId: nil, isRegular: true, isTerminated: false, ownBundleId: nil))
    }

    @Test func hidesDockyardItself() {
        #expect(!AppFilter.shouldShow(bundleId: "local.dockyard", isRegular: true, isTerminated: false, ownBundleId: "local.dockyard"))
    }
}
