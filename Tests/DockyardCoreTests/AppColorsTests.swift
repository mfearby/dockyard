import DockyardCore
import Foundation
import Testing

struct AppColorsTests {
    @Test func normalisesHexColours() {
        #expect(AppColors.normalize("#ABCDEF") == "#abcdef")
        #expect(AppColors.normalize(" #00ff00 ") == "#00ff00")
    }

    @Test func rejectsAnythingElse() {
        for bad in ["", "#abc", "abcdef", "#abcdeg", "#abcdef0", "red", "#12 456", "url(x)", "#ff0000;x"] {
            #expect(AppColors.normalize(bad) == nil, "\(bad)")
        }
    }

    @Test func paletteColoursAreValidAndDistinct() {
        for color in AppColors.palette { #expect(AppColors.normalize(color) == color) }
        #expect(Set(AppColors.palette).count == AppColors.palette.count)
    }

    @Test func defaultIsTheFirstUnusedPaletteColour() {
        let palette = AppColors.palette
        #expect(AppColors.nextDefault(used: []) == palette[0])
        #expect(AppColors.nextDefault(used: [palette[0], palette[2]]) == palette[1])
        // Once every colour is taken, it cycles.
        #expect(AppColors.nextDefault(used: palette) == palette[0])
    }

    @Test func addingAnAppGivesItTheNextDefaultColour() {
        var prefs = Preferences()
        let first = prefs.add("com.apple.Notes", to: .appColors)
        let second = prefs.add("com.apple.finder", to: .appColors)
        let again = prefs.add("com.apple.Notes", to: .appColors)
        #expect(first && second && !again)
        #expect(prefs.appColors == ["com.apple.Notes": AppColors.palette[0], "com.apple.finder": AppColors.palette[1]])
        #expect(prefs.items(in: .appColors) == ["com.apple.Notes", "com.apple.finder"])
    }

    @Test func configDropsInvalidColoursAndRoundTrips() throws {
        let json = ##"{"preferences": {"appColors": {"com.apple.Notes": "#FF0000", "com.apple.finder": "nope"}}}"##
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.preferences.appColors == ["com.apple.Notes": "#ff0000"])
        let encoded = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Config.self, from: encoded).preferences.appColors == ["com.apple.Notes": "#ff0000"])
    }

    @Test func noColoursByDefault() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"preferences": {}}"#.utf8))
        #expect(config.preferences.appColors.isEmpty)
    }
}
