import DockyardCore
import Foundation
import Testing

struct ConfigTests {
    /// A store in a fresh temp directory that doesn't exist yet.
    private func makeStore() -> ConfigStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dockyard-tests-\(UUID().uuidString)")
        return ConfigStore(url: dir.appendingPathComponent("nested/config.json"))
    }

    @Test func missingFileLoadsDefaults() {
        #expect(makeStore().load() == Config())
    }

    @Test func saveCreatesDirectoriesAndRoundTrips() throws {
        let store = makeStore()
        let config = Config(order: ["com.apple.Notes", "com.microsoft.Outlook"],
                            preferences: Preferences(hideHiddenApps: true, hideAppsWithoutWindows: true, barHeight: 36))
        try store.save(config)
        #expect(store.load() == config)
    }

    @Test func malformedFileLoadsDefaults() throws {
        let store = makeStore()
        try store.save(Config(order: ["a"]))
        try Data("{ not json".utf8).write(to: store.url)
        #expect(store.load() == Config())
    }

    @Test func missingKeysUseDefaults() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(config == Config())
    }

    @Test func unknownKeysAreIgnored() throws {
        let json = #"{"order": ["a"], "someFutureSetting": true}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.order == ["a"])
    }

    @Test func configWithoutPreferencesGetsDefaults() throws {
        // Config files written before the Options screen existed.
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"order": ["a"]}"#.utf8))
        #expect(config.preferences == Preferences())
    }

    @Test func partialPreferencesFillInDefaults() throws {
        let json = #"{"preferences": {"hideHiddenApps": true}}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.preferences == Preferences(hideHiddenApps: true, hideAppsWithoutWindows: false))
    }

    @Test func barHeightDefaultsTo40() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"preferences": {}}"#.utf8))
        #expect(config.preferences.barHeight == 40)
    }

    @Test func outOfRangeBarHeightIsClampedOnLoad() throws {
        // A hand-edited config shouldn't be able to make the bar unusably small or huge.
        let tiny = try JSONDecoder().decode(Config.self, from: Data(#"{"preferences": {"barHeight": 2}}"#.utf8))
        let huge = try JSONDecoder().decode(Config.self, from: Data(#"{"preferences": {"barHeight": 900}}"#.utf8))
        #expect(tiny.preferences.barHeight == 28)
        #expect(huge.preferences.barHeight == 64)
    }

    @Test func barHeightIsClampedWhenSet() {
        var prefs = Preferences()
        prefs.barHeight = 10
        #expect(prefs.barHeight == 28)
        prefs.barHeight = 36
        #expect(prefs.barHeight == 36)
    }

    @Test func barStartsExpanded() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"order": ["a"]}"#.utf8))
        #expect(config.collapsed == false)
    }

    @Test func collapsedStateRoundTrips() throws {
        let store = makeStore()
        try store.save(Config(collapsed: true))
        #expect(store.load().collapsed == true)
    }

    @Test func screenSpaceDefaultsToCoveringTheDock() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"preferences": {}}"#.utf8))
        #expect(config.preferences.screenSpace == .coverDock)
    }

    @Test func screenSpaceRoundTrips() throws {
        let store = makeStore()
        try store.save(Config(preferences: Preferences(screenSpace: .moveWindows)))
        #expect(store.load().preferences.screenSpace == .moveWindows)
    }

    @Test func unknownScreenSpaceFallsBackWithoutLosingOtherSettings() throws {
        let json = #"{"order": ["a"], "preferences": {"screenSpace": "fromTheFuture", "barHeight": 36}}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.preferences.screenSpace == .coverDock)
        #expect(config.preferences.barHeight == 36)
        #expect(config.order == ["a"])
    }

    @Test func windowsAreGroupedByDefault() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"preferences": {}}"#.utf8))
        #expect(config.preferences.separateWindows == false)
    }

    @Test func separateWindowsRoundTrips() throws {
        let store = makeStore()
        try store.save(Config(preferences: Preferences(separateWindows: true)))
        #expect(store.load().preferences.separateWindows == true)
    }

    @Test func excludedAppsDefaultToNone() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"preferences": {}}"#.utf8))
        #expect(config.preferences.excludedApps.isEmpty)
    }

    @Test func excludedAppsRoundTripInOrder() throws {
        let store = makeStore()
        try store.save(Config(preferences: Preferences(excludedApps: ["com.spotify.client", "com.apple.Music"])))
        #expect(store.load().preferences.excludedApps == ["com.spotify.client", "com.apple.Music"])
    }

    @Test func themeDefaultsToLight() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"preferences": {}}"#.utf8))
        #expect(config.preferences.theme == .light)
    }

    @Test func themeRoundTripsAndUnknownValuesFallBack() throws {
        let store = makeStore()
        try store.save(Config(preferences: Preferences(theme: .dark)))
        #expect(store.load().preferences.theme == .dark)
        let json = #"{"preferences": {"theme": "neon", "barHeight": 36}}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.preferences.theme == .light)
        #expect(config.preferences.barHeight == 36)
    }

    @Test func quickLaunchDefaultsToEmptyAndRoundTripsInOrder() throws {
        let empty = try JSONDecoder().decode(Config.self, from: Data(#"{"preferences": {}}"#.utf8))
        #expect(empty.preferences.quickLaunch.isEmpty)
        let store = makeStore()
        try store.save(Config(preferences: Preferences(quickLaunch: ["com.apple.screenshot.launcher", "com.apple.Notes"])))
        #expect(store.load().preferences.quickLaunch == ["com.apple.screenshot.launcher", "com.apple.Notes"])
    }

    @Test func addingToAListAppendsOnce() {
        var prefs = Preferences()
        let first = prefs.add("com.apple.Notes", to: .quickLaunch)
        let second = prefs.add("com.apple.finder", to: .quickLaunch)
        let duplicate = prefs.add("com.apple.Notes", to: .quickLaunch)
        #expect(first && second && !duplicate)
        #expect(prefs.quickLaunch == ["com.apple.Notes", "com.apple.finder"])
    }

    @Test func listsAreIndependent() {
        var prefs = Preferences()
        prefs.add("com.spotify.client", to: .excludedApps)
        let added = prefs.add("com.spotify.client", to: .quickLaunch)
        #expect(added)
        #expect(prefs.apps(in: .excludedApps) == ["com.spotify.client"])
        #expect(prefs.apps(in: .quickLaunch) == ["com.spotify.client"])
    }
}
