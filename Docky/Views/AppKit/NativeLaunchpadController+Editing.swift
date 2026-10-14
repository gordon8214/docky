import AppKit

extension NativeLaunchpadController {
    func layoutFolderID(_ folder: AppFolderTile) -> String {
        let prefix = "virtual:"
        return folder.identifier.hasPrefix(prefix)
            ? String(folder.identifier.dropFirst(prefix.count)) : folder.identifier
    }
    func folderItem(_ folder: AppFolderTile) -> NativeBrowserItem {
        NativeBrowserItem(
            id: "folder:\(layoutFolderID(folder))", title: folder.displayName,
            image: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: folder.displayName),
            actions: [
                .action(String(localized: "Rename")) { [weak self] in self?.rename(folder) },
                .action(String(localized: "Ungroup")) { [weak self] in
                    guard let self else { return }
                    self.layoutService.ungroupFolder(id: self.layoutFolderID(folder))
                }
            ]
        ) { [weak self] in
            self?.folder = folder
            self?.query = ""
            self?.search.stringValue = ""
            self?.refresh()
        }
    }
    func applyDrop(id: String, at boundary: Int, operation: NSCollectionView.DropOperation) -> Bool {
        let service = layoutService
        if let folder, id.hasPrefix("app:") {
            let folderID = layoutFolderID(folder)
            guard let stored = service.folder(withID: folderID),
                let source = stored.bundleIDs.firstIndex(of: String(id.dropFirst(4))) else { return false }
            service.moveAppInFolder(
                folderID: folderID, bundleID: String(id.dropFirst(4)),
                toIndex: boundary - (operation == .before && source < boundary ? 1 : 0))
        } else if operation == .on, id.hasPrefix("app:"), displayed.indices.contains(boundary) {
            return mergeApp(String(id.dropFirst(4)), into: displayed[boundary].id)
        } else {
            if id.hasPrefix("app:") { service.removeFromFolder(bundleID: String(id.dropFirst(4))) }
            guard let source = service.layout.items.firstIndex(where: { $0.id == id }) else { return false }
            let target: Int
            if displayed.indices.contains(boundary),
                let anchor = service.layout.items.firstIndex(where: { $0.id == displayed[boundary].id }) {
                target = anchor
            } else { target = service.layout.items.count }
            service.moveItem(id: id, toIndex: target - (source < target ? 1 : 0))
        }
        return true
    }
    private func mergeApp(_ bundleID: String, into target: String) -> Bool {
        let service = layoutService
        guard service.allReferencedBundleIDs.contains(bundleID) else { return false }
        if target.hasPrefix("folder:") {
            let folderID = String(target.dropFirst(7))
            guard let stored = service.folder(withID: folderID) else { return false }
            if !stored.bundleIDs.contains(bundleID) { service.addApp(bundleID: bundleID, toFolderWithID: folderID) }
            return true
        }
        guard target.hasPrefix("app:"), service.layout.items.contains(where: { $0.id == target }) else { return false }
        return service.createFolder(
            merging: bundleID, intoSlotOf: String(target.dropFirst(4)), name: String(localized: "New Folder")) != nil
    }
}
