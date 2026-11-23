import DockyardCore
import Foundation
import Testing

struct LaunchTrackerTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// A tracker that has already seen pid 1 running (an app open before Dockyard started).
    private func makeTracker() -> LaunchTracker {
        let tracker = LaunchTracker()
        tracker.update(pids: [1], now: t0)
        return tracker
    }

    private func loading(_ tracker: LaunchTracker, finished: Bool, windows: Int?, at seconds: TimeInterval,
                         visible: Bool = true) -> Bool {
        tracker.isLoading(pid: 2, finishedLaunching: finished, windowCount: windows, windowsVisible: visible,
                          launchDate: t0, now: t0.addingTimeInterval(seconds))
    }

    @Test func followsGIMPsRealLaunch() {
        // From a real launch: finished launching at 8.3s, first window at 16.2s.
        let tracker = makeTracker()
        tracker.update(pids: [1, 2], now: t0.addingTimeInterval(6.6))
        #expect(loading(tracker, finished: false, windows: nil, at: 6.6))
        #expect(loading(tracker, finished: false, windows: 0, at: 7.5))
        #expect(loading(tracker, finished: true, windows: nil, at: 8.3))
        #expect(loading(tracker, finished: true, windows: 0, at: 13.1))
        #expect(!loading(tracker, finished: true, windows: 1, at: 16.2))
    }

    @Test func closingTheLastWindowLaterIsNotLoading() {
        let tracker = makeTracker()
        tracker.update(pids: [1, 2], now: t0)
        #expect(!loading(tracker, finished: true, windows: 1, at: 2))
        #expect(!loading(tracker, finished: true, windows: 0, at: 5))
    }

    @Test func givesUpAfterTheTimeout() {
        let tracker = makeTracker()
        tracker.update(pids: [1, 2], now: t0)
        #expect(loading(tracker, finished: true, windows: 0, at: LaunchTracker.timeout - 1))
        #expect(!loading(tracker, finished: true, windows: 0, at: LaunchTracker.timeout + 1))
        // Also for an app that never reports finishing.
        #expect(!loading(tracker, finished: false, windows: 0, at: LaunchTracker.timeout + 1))
    }

    @Test func withoutWindowAccessItEndsWhenLaunchingFinishes() {
        let tracker = makeTracker()
        tracker.update(pids: [1, 2], now: t0)
        #expect(loading(tracker, finished: false, windows: nil, at: 1, visible: false))
        #expect(!loading(tracker, finished: true, windows: nil, at: 2, visible: false))
    }

    @Test func appsOpenBeforeDockyardStartedAreNeverLoading() {
        let tracker = makeTracker()
        #expect(!tracker.isLoading(pid: 1, finishedLaunching: false, windowCount: 0, windowsVisible: true,
                                   launchDate: t0, now: t0.addingTimeInterval(1)))
        #expect(!tracker.inLaunchPhase(pid: 1, launchDate: t0, now: t0.addingTimeInterval(1)))
    }

    @Test func usesFirstSeenWhenThereIsNoLaunchDate() {
        let tracker = makeTracker()
        tracker.update(pids: [1, 2], now: t0)
        #expect(tracker.isLoading(pid: 2, finishedLaunching: true, windowCount: 0, windowsVisible: true,
                                  launchDate: nil, now: t0.addingTimeInterval(10)))
        #expect(tracker.inLaunchPhase(pid: 2, launchDate: nil, now: t0.addingTimeInterval(10)))
    }

    @Test func forgetsQuitApps() {
        let tracker = makeTracker()
        tracker.update(pids: [1, 2], now: t0)
        _ = loading(tracker, finished: true, windows: 1, at: 1)
        tracker.update(pids: [1], now: t0.addingTimeInterval(2))
        // The same pid reused by a new launch starts fresh.
        tracker.update(pids: [1, 2], now: t0.addingTimeInterval(3))
        #expect(tracker.isLoading(pid: 2, finishedLaunching: true, windowCount: 0, windowsVisible: true,
                                  launchDate: t0.addingTimeInterval(3), now: t0.addingTimeInterval(4)))
    }
}
