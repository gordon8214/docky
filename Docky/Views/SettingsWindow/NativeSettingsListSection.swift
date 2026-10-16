import AppKit

/// A section listing items, one row per item. Updating it keeps the rows for
/// items that remain, so their focus and state survive.
final class NativeSettingsListSection: NativeSettingsSection {
    private let emptyRow: NativeFormTextRow
    private var itemRows: [String: NativeFormRowView] = [:]

    init(_ header: String? = nil, footer: String? = nil, emptyText: String, actions: [NSView] = []) {
        emptyRow = NativeFormTextRow(emptyText, secondary: true)
        super.init(header, footer: footer, rows: [emptyRow], actions: actions)
    }

    required init?(coder: NSCoder) { nil }

    /// Shows one row per item, in order. `make` builds a row for a new item;
    /// `update` refreshes the row of an item that was already listed.
    func reconcile<Item>(
        _ items: [Item], id: (Item) -> String, make: (Item) -> NativeFormRowView,
        update: (NativeFormRowView, Item) -> Void
    ) {
        var rowsByID: [String: NativeFormRowView] = [:]
        var ordered: [NativeFormRowView] = []
        for item in items {
            let key = id(item)
            guard rowsByID[key] == nil else { continue }
            let row: NativeFormRowView
            if let existing = itemRows[key] {
                row = existing
                update(existing, item)
            } else {
                row = make(item)
            }
            rowsByID[key] = row
            ordered.append(row)
        }
        itemRows = rowsByID
        setRows(ordered.isEmpty ? [emptyRow] : ordered)
    }
}
