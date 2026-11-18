import Foundation

/// User settings stored in ~/.config/dockyard/config.json.
public struct Config: Codable, Equatable {
    /// Bundle IDs in the order the user arranged them on the bar.
    public var order: [String]

    public init(order: [String] = []) {
        self.order = order
    }

    // Missing keys fall back to defaults so older config files keep loading as fields are added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = try c.decodeIfPresent([String].self, forKey: .order) ?? []
    }
}

public struct ConfigStore {
    public static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/dockyard/config.json")

    public let url: URL

    public init(url: URL = ConfigStore.defaultURL) {
        self.url = url
    }

    /// Returns defaults if the file is missing or unreadable, so a bad config never stops the bar starting.
    public func load() -> Config {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        return config
    }

    public func save(_ config: Config) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
