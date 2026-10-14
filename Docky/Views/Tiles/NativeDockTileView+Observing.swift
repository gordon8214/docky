import AppKit
import Combine

extension NativeDockTileView {
    func installObservers() {
        for publisher in [
            WorkspaceService.shared.objectWillChange.eraseToAnyPublisher(),
            WindowRegistry.shared.objectWillChange.eraseToAnyPublisher(),
            DockBadgeService.shared.objectWillChange.eraseToAnyPublisher(),
            TilePressService.shared.objectWillChange.eraseToAnyPublisher(),
            StartMenuService.shared.objectWillChange.eraseToAnyPublisher(),
            TrashService.shared.objectWillChange.eraseToAnyPublisher(),
            WidgetExpansionWindowController.shared.objectWillChange.eraseToAnyPublisher()
        ] {
            publisher.sink { [weak self] in DispatchQueue.main.async { self?.refresh() } }.store(in: &subscriptions)
        }
        FolderAccessService.shared.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                self?.folderPreviewNeedsRefresh = true
                self?.refresh()
            }
        }.store(in: &subscriptions)
        observeChanges { [weak self] in
            guard let self else { return }
            _ = self.interaction.preferences.effectiveTileIconPadding
            _ = self.interaction.preferences.effectiveTileHoverScale
            _ = self.interaction.preferences.effectiveTileHoverOpacity
            _ = self.interaction.preferences.effectiveActiveIndicatorColor
            _ = self.interaction.preferences.dimsIdleAppIcons
            self.refresh()
        }.store(in: &subscriptions)
        DockDragService.shared.$springLoadedTileID.sink { [weak self] id in
            guard let self else { return }
            guard id == self.interaction.tile.id else {
                if self.wasSpringLoaded {
                    self.folderPopover?.close()
                    self.fan?.dismiss()
                    self.wasSpringLoaded = false
                }
                return
            }
            self.wasSpringLoaded = true
            switch self.interaction.tile.content {
            case .folder:
                self.interaction.isFolderPopoverPresented = true
                self.showFolderPopover()
            case .appFolder:
                self.interaction.isAppFolderPopoverPresented = true
                self.showFolderPopover()
            default: break
            }
        }.store(in: &subscriptions)
    }
}
