//
//  WindowRecencyOrder.swift
//  Docky
//
//  Docky's window list order, most recently used first, like Windows 11
//  Alt+Tab. No SkyLight or AX calls live here, so the standalone browser test
//  can compile it.
//

nonisolated enum WindowRecencyOrder {
    /// Merges a fresh window list into `current`. Known windows keep their
    /// slot and take the snapshot's fields. New windows go right after the
    /// current front window, those on an active Space first, in snapshot
    /// order, so a window that opens without focus is the next one a quick
    /// switch reaches. `front`, a window known to have focus, goes first.
    static func merged<Window: Identifiable>(
        current: [Window],
        snapshot: [Window],
        front: Window.ID?,
        isOnActiveSpace: (Window) -> Bool
    ) -> [Window] {
        let snapshotByID = Dictionary(snapshot.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<Window.ID>()
        var merged: [Window] = []
        for window in current {
            guard let updated = snapshotByID[window.id], seen.insert(window.id).inserted else { continue }
            merged.append(updated)
        }
        let newcomers = snapshot.filter { seen.insert($0.id).inserted }
        let arrivals = newcomers.filter(isOnActiveSpace) + newcomers.filter { !isOnActiveSpace($0) }
        merged.insert(contentsOf: arrivals, at: min(1, merged.count))
        if let front, let index = merged.firstIndex(where: { $0.id == front }) {
            merged.insert(merged.remove(at: index), at: 0)
        }
        return merged
    }
}
