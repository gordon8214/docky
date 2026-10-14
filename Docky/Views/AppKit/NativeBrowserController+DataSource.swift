import AppKit

extension NativeBrowserController {
    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        displayed.count
    }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath)
        -> NSCollectionViewItem {
        guard
            let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("item"), for: indexPath)
                as? NativeBrowserCollectionItem
        else { return NSCollectionViewItem() }
        item.configure(displayed[indexPath.item], controller: self)
        return item
    }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let index = indexPaths.first?.item, displayed.indices.contains(index) else { return }
        selectionID = displayed[index].id
        onSelection?(displayed[index].id)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { displayed.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = displayed[row]
        let image = NSImageView(image: item.image ?? NSImage())
        image.imageScaling = .scaleProportionallyUpOrDown
        image.widthAnchor.constraint(equalToConstant: 44).isActive = true
        image.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return nativeStack(
            [
                image,
                nativeStack(
                    [nativeLabel(item.title), nativeLabel(item.detail, size: 11, color: .secondaryLabelColor)],
                    spacing: 2)
            ], orientation: .horizontal)
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard displayed.indices.contains(table.selectedRow) else { return }
        selectionID = displayed[table.selectedRow].id
        onSelection?(displayed[table.selectedRow].id)
    }
}
