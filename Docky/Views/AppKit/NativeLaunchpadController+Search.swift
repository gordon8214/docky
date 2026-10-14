import AppKit

extension NativeLaunchpadController {
    func launcherFilteredItems() -> [NativeBrowserItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return items }
        return items.compactMap { item -> (NativeBrowserItem, Int)? in
            let score = matchScore(item, query: query)
            return score == Int.max ? nil : (item, score)
        }.sorted { left, right in
            left.1 == right.1
                ? left.0.title.localizedStandardCompare(right.0.title) == .orderedAscending : left.1 < right.1
        }.map { $0.0 }
    }
    func matchScore(_ item: NativeBrowserItem, query: String) -> Int {
        let loweredQuery = query.lowercased()
        let name = item.title.lowercased()
        if name == loweredQuery { return 0 }
        if name.hasPrefix(loweredQuery) { return 1 }
        if let range = name.range(of: loweredQuery) {
            return 10 + name.distance(from: name.startIndex, to: range.lowerBound)
        }
        guard item.id.hasPrefix("app:") else { return Int.max }
        let identifier = String(item.id.dropFirst(4)).lowercased()
        if identifier == loweredQuery { return 100 }
        if identifier.hasPrefix(loweredQuery) { return 101 }
        if let range = identifier.range(of: loweredQuery) {
            return 110 + identifier.distance(from: identifier.startIndex, to: range.lowerBound)
        }
        return Int.max
    }
    func sortedEntries(_ entries: [LaunchpadEntry]) -> [LaunchpadEntry] {
        switch preferences.launchpadSortMode {
        case .manual:
            return entries
        case .name:
            return entries.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .dateCreated:
            return entries.sorted { compareByDate($0, $1, \.created) }
        case .dateModified:
            return entries.sorted { compareByDate($0, $1, \.modified) }
        }
    }

    func compareByDate(
        _ lhs: LaunchpadEntry,
        _ rhs: LaunchpadEntry,
        _ keyPath: KeyPath<LaunchpadAppDates, Date>
    ) -> Bool {
        let lhsDate = representativeDate(for: lhs, keyPath)
        let rhsDate = representativeDate(for: rhs, keyPath)
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    /// Date used to sort an entry. Apps read their own bundle date;
    /// folders use their most-recent member so a folder containing a
    /// freshly-installed app sorts up alongside it.
    func representativeDate(
        for entry: LaunchpadEntry,
        _ keyPath: KeyPath<LaunchpadAppDates, Date>
    ) -> Date {
        switch entry {
        case .app(let app):
            return overlay.appDatesByBundleID[app.bundleIdentifier]?[keyPath: keyPath] ?? .distantPast
        case .folder(let folder):
            return folder.apps
                .compactMap { overlay.appDatesByBundleID[$0.bundleIdentifier]?[keyPath: keyPath] }
                .max() ?? .distantPast
        }
    }

}
