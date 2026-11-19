/// Gives each window a stable serial number and keeps a stable order for each app's window buttons.
///
/// Accessibility lists windows front to back, so using that order directly would shuffle the buttons every
/// time the user switched windows. Instead, windows keep the order they were first seen in (or the order the
/// user dragged them into), and new windows go after the app's existing ones.
///
/// Generic over the window key so it can be tested without real windows.
public final class WindowRegistry<Key: Hashable> {
    private struct Entry {
        let key: Key
        let serial: Int
    }

    private var windows: [Int32: [Entry]] = [:]
    private var nextSerial = 1

    public init() {}

    /// Records `pid`'s current windows and returns them in button order, each with its serial.
    /// Windows that have closed are forgotten.
    @discardableResult
    public func update(pid: Int32, keys: [Key]) -> [(key: Key, serial: Int)] {
        let current = Set(keys)
        var entries = (windows[pid] ?? []).filter { current.contains($0.key) }
        let known = Set(entries.map(\.key))
        var added = Set<Key>()
        for key in keys where !known.contains(key) && added.insert(key).inserted {
            entries.append(Entry(key: key, serial: nextSerial))
            nextSerial += 1
        }
        windows[pid] = entries
        return entries.map { ($0.key, $0.serial) }
    }

    /// Forgets apps that are no longer running.
    public func retain(pids: Set<Int32>) {
        windows = windows.filter { pids.contains($0.key) }
    }

    public func lookup(serial: Int) -> (pid: Int32, key: Key)? {
        for (pid, entries) in windows {
            if let entry = entries.first(where: { $0.serial == serial }) { return (pid, entry.key) }
        }
        return nil
    }

    /// Reorders each app's windows to match `serials`, the order the user dragged the buttons into.
    /// Windows missing from `serials` keep their relative order after the others.
    public func reorder(serials: [Int]) {
        var rank: [Int: Int] = [:]
        for (i, serial) in serials.enumerated() where rank[serial] == nil { rank[serial] = i }
        for (pid, entries) in windows {
            windows[pid] = entries.enumerated().sorted { a, b in
                let ra = rank[a.element.serial] ?? Int.max
                let rb = rank[b.element.serial] ?? Int.max
                return ra != rb ? ra < rb : a.offset < b.offset
            }.map(\.element)
        }
    }
}
