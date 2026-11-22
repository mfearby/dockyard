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

    @Test func bundleOrderFromWindowButtons() {
        // Two IntelliJ windows either side of Notes: IntelliJ's position is that of its first button.
        let ids = ["com.jetbrains.intellij#3", "com.apple.Notes", "com.jetbrains.intellij#1", "com.apple.finder"]
        #expect(AppOrdering.bundleOrder(fromButtonIDs: ids) == ["com.jetbrains.intellij", "com.apple.Notes", "com.apple.finder"])
    }

    @Test func mergeIntoEmptySavedOrder() {
        #expect(AppOrdering.merged(newOrder: ["b", "a"], into: []) == ["b", "a"])
    }
}

struct AppButtonClickTests {
    @Test func firstClickOnABackgroundAppJustBringsItForward() {
        #expect(AppButtonClick.action(isFrontmost: false, windowCount: 3) == .activate)
    }

    @Test func clickingTheFrontAppListsItsWindows() {
        #expect(AppButtonClick.action(isFrontmost: true, windowCount: 2) == .showWindowMenu)
        #expect(AppButtonClick.action(isFrontmost: true, windowCount: 5) == .showWindowMenu)
    }

    @Test func noMenuForOneWindowOrNone() {
        #expect(AppButtonClick.action(isFrontmost: true, windowCount: 1) == .activate)
        #expect(AppButtonClick.action(isFrontmost: true, windowCount: 0) == .activate)
    }
}

struct AppFilterTests {
    private let me = "local.dockyard"

    private func shows(_ app: AppSnapshot, _ prefs: Preferences = Preferences()) -> Bool {
        AppFilter.shouldShow(app, preferences: prefs, ownBundleId: me)
    }

    @Test func showsOrdinaryApps() {
        #expect(shows(AppSnapshot(bundleId: "com.apple.Notes")))
    }

    @Test func hidesBackgroundAppsAndAgents() {
        #expect(!shows(AppSnapshot(bundleId: "com.apple.Notes", isRegular: false)))
    }

    @Test func hidesTerminatedApps() {
        #expect(!shows(AppSnapshot(bundleId: "com.apple.Notes", isTerminated: true)))
    }

    @Test func hidesAppsWithoutBundleId() {
        #expect(!shows(AppSnapshot(bundleId: nil)))
    }

    @Test func hidesDockyardItself() {
        #expect(!shows(AppSnapshot(bundleId: me)))
    }

    @Test func excludedAppsNeverShow() {
        let prefs = Preferences(excludedApps: ["com.spotify.client"])
        #expect(!shows(AppSnapshot(bundleId: "com.spotify.client"), prefs))
        #expect(!shows(AppSnapshot(bundleId: "com.spotify.client", isHidden: true), prefs))
        #expect(shows(AppSnapshot(bundleId: "com.apple.Notes"), prefs))
    }

    @Test func hiddenAppsShowByDefault() {
        #expect(shows(AppSnapshot(bundleId: "com.apple.Notes", isHidden: true)))
    }

    @Test func hiddenAppsCanBeHidden() {
        #expect(!shows(AppSnapshot(bundleId: "com.apple.Notes", isHidden: true), Preferences(hideHiddenApps: true)))
    }

    @Test func windowlessAppsShowByDefault() {
        #expect(shows(AppSnapshot(bundleId: "com.apple.finder", windowCount: 0)))
    }

    @Test func windowlessAppsCanBeHidden() {
        let prefs = Preferences(hideAppsWithoutWindows: true)
        #expect(!shows(AppSnapshot(bundleId: "com.apple.finder", windowCount: 0), prefs))
        #expect(shows(AppSnapshot(bundleId: "com.apple.finder", windowCount: 1), prefs))
    }

    @Test func unknownWindowCountKeepsTheApp() {
        #expect(shows(AppSnapshot(bundleId: "com.apple.finder", windowCount: nil), Preferences(hideAppsWithoutWindows: true)))
    }

    @Test func hiddenAppsIgnoreTheWindowRule() {
        // A hidden app's windows are off screen; only hideHiddenApps should decide whether it shows.
        let hidden = AppSnapshot(bundleId: "com.apple.Notes", isHidden: true, windowCount: 0)
        #expect(shows(hidden, Preferences(hideAppsWithoutWindows: true)))
        #expect(!shows(hidden, Preferences(hideHiddenApps: true, hideAppsWithoutWindows: true)))
    }
}
