import Foundation

/// Taskbar button colours that users give to apps (see `Preferences.appColors`).
///
/// Colours come from the Options page and end up in the bar's styles, so only plain "#rrggbb" values are accepted.
public enum AppColors {
    /// The swatches offered in Options, and the defaults given to newly added apps in this order: a softer take on
    /// the Windows 16-colour palette, without its black, white and greys.
    public static let palette = [
        "#031b75", "#108c00", "#17bbd3", "#720c0a", "#6c1c9e", "#b25116",
        "#0b63c4", "#9bce00", "#73f5d5", "#e89e00", "#ff7bdb", "#fef255",
    ]

    /// The colour as lowercase "#rrggbb", or nil if it isn't one.
    public static func normalize(_ value: String) -> String? {
        let s = value.trimmingCharacters(in: .whitespaces).lowercased()
        guard s.count == 7, s.first == "#", s.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
        return s
    }

    /// Keeps only entries whose colour is valid, normalised.
    public static func validated(_ colors: [String: String]) -> [String: String] {
        colors.compactMapValues(normalize)
    }

    /// The colour for a newly added app: the first palette colour no other app uses, cycling once all are taken.
    public static func nextDefault(used: [String]) -> String {
        palette.first { !used.contains($0) } ?? palette[used.count % palette.count]
    }
}
