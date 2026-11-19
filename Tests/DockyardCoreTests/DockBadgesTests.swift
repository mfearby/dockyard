import DockyardCore
import Testing

struct DockBadgesTests {
    private let apps = [
        "/Applications/Microsoft Outlook.app": "com.microsoft.Outlook",
        "/Applications/Microsoft Teams.app": "com.microsoft.teams2",
        "/System/Applications/Notes.app": "com.apple.Notes",
    ]

    @Test func matchesBadgesToRunningApps() {
        let items = [
            DockBadges.Item(appPath: "/Applications/Microsoft Outlook.app", label: "1"),
            DockBadges.Item(appPath: "/Applications/Microsoft Teams.app", label: "99+"),
            DockBadges.Item(appPath: "/System/Applications/Notes.app", label: nil),
        ]
        #expect(DockBadges.match(items, apps: apps) == ["com.microsoft.Outlook": "1", "com.microsoft.teams2": "99+"])
    }

    @Test func ignoresBadgesForAppsThatArentRunning() {
        // Pinned Dock items for apps that aren't open, plus Finder folders and the Trash.
        let items = [DockBadges.Item(appPath: "/Applications/Slack.app", label: "3")]
        #expect(DockBadges.match(items, apps: apps).isEmpty)
    }

    @Test func toleratesTrailingSlashesInPaths() {
        let items = [DockBadges.Item(appPath: "/Applications/Microsoft Outlook.app/", label: "2")]
        #expect(DockBadges.match(items, apps: apps) == ["com.microsoft.Outlook": "2"])
    }

    @Test func emptyOrBlankLabelsMeanNoBadge() {
        #expect(DockBadges.normalize(nil) == nil)
        #expect(DockBadges.normalize("") == nil)
        #expect(DockBadges.normalize("  ") == nil)
        #expect(DockBadges.normalize(" 5 ") == "5")
        #expect(DockBadges.normalize("\u{2022}") == "\u{2022}")  // some apps badge with a dot
    }
}
