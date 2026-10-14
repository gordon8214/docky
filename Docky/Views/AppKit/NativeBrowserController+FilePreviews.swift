import AppKit

extension NativeBrowserController {
    func filePreview(for url: URL) -> NSImage {
        let cache = IconCacheService.shared
        let extent = IconCacheService.gridThumbnailPixelExtent
        if let image = cache.cachedPreviewThumbnail(forFileURL: url, maxPixelSize: extent) { return image }
        if previewTasks[url] == nil {
            previewTasks[url] = Task { [weak self] in
                let image = await cache.loadPreviewThumbnailAsync(forFileURL: url, maxPixelSize: extent)
                guard !Task.isCancelled, let self else { return }
                self.previewTasks[url] = nil
                guard let image, let index = self.items.firstIndex(where: { $0.url == url }) else { return }
                self.items[index].image = image
                self.reload()
            }
        }
        return cache.icon(forFileURL: url)
    }
}
