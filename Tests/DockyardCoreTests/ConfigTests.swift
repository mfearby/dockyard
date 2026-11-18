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
                            preferences: Preferences(hideHiddenApps: true, hideAppsWithoutWindows: true))
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
}
