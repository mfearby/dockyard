import Foundation

/// Decides whether an app is still starting up, for the hourglass on its button.
///
/// macOS marks an app as finished launching when the Dock stops bouncing it, but apps like GIMP and Office open
/// their first window several seconds later. So an app counts as loading until it has finished launching and,
/// when Dockyard can see windows, until its first window appears. Either way, only for `timeout` after it started,
/// so an app that never opens a window (or never reports finishing) doesn't show an hourglass forever.
public final class LaunchTracker {
    public static let timeout: TimeInterval = 45

    /// When each process was first seen, used when macOS doesn't report a launch date.
    private var firstSeen: [Int32: Date] = [:]
    private var hadWindow = Set<Int32>()
    /// Processes that were already running when tracking started; they aren't launches.
    private var existing: Set<Int32>?

    public init() {}

    /// Records the processes running now and forgets ones that have quit. The first call marks everything running
    /// as already open, so apps started before Dockyard never show as loading.
    public func update(pids: Set<Int32>, now: Date = Date()) {
        if existing == nil { existing = pids }
        existing?.formIntersection(pids)
        for pid in pids where firstSeen[pid] == nil { firstSeen[pid] = now }
        firstSeen = firstSeen.filter { pids.contains($0.key) }
        hadWindow.formIntersection(pids)
    }

    /// Whether the app started recently and hasn't had a window yet, so its windows are worth checking.
    public func inLaunchPhase(pid: Int32, launchDate: Date?, now: Date = Date()) -> Bool {
        withinTimeout(pid: pid, launchDate: launchDate, now: now) && !hadWindow.contains(pid)
    }

    /// - Parameters:
    ///   - windowCount: the app's windows, or nil if they couldn't be read (the app didn't answer).
    ///   - windowsVisible: whether Dockyard can read windows at all (Accessibility access). Without it, loading
    ///     ends when the app finishes launching.
    public func isLoading(pid: Int32, finishedLaunching: Bool, windowCount: Int?, windowsVisible: Bool,
                          launchDate: Date?, now: Date = Date()) -> Bool {
        if let windowCount, windowCount > 0 { hadWindow.insert(pid) }
        guard withinTimeout(pid: pid, launchDate: launchDate, now: now) else { return false }
        if !finishedLaunching { return true }
        return windowsVisible && !hadWindow.contains(pid)
    }

    private func withinTimeout(pid: Int32, launchDate: Date?, now: Date) -> Bool {
        guard existing?.contains(pid) != true, let start = launchDate ?? firstSeen[pid] else { return false }
        return now.timeIntervalSince(start) < Self.timeout
    }
}
