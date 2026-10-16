import Foundation

struct SettingsNavigationHistory {
    private(set) var entries: [String] = []
    private(set) var index = -1
    var current: String? { entries.indices.contains(index) ? entries[index] : nil }
    var canMoveBack: Bool { index > 0 }
    var canMoveForward: Bool { index + 1 < entries.count }

    mutating func push(_ paneID: String) {
        guard current != paneID else { return }
        entries = Array(entries.prefix(index + 1)) + [paneID]
        index = entries.count - 1
    }

    mutating func move(_ delta: Int) -> String? {
        let destination = index + delta
        guard entries.indices.contains(destination) else { return nil }
        index = destination
        return entries[index]
    }
}
