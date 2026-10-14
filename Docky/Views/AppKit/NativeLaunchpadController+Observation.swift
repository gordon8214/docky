import AppKit
import Combine

extension NativeLaunchpadController {
    func configureObservers() {
        let observedPublisher1 = NotificationCenter.default.publisher(
            for: NSScrollView.didEndLiveScrollNotification, object: scroll)
        observations.add { [weak self] in
            observedPublisher1.sink { [weak self] _ in self?.snapToPage() }
        }
        let observedPublisher2 = NotificationCenter.default.publisher(
            for: NSView.boundsDidChangeNotification, object: scroll.contentView)
        observations.add { [weak self] in
            observedPublisher2.sink { [weak self] _ in self?.updatePageLabel() }
        }
        scroll.contentView.postsBoundsChangedNotifications = true
        let observedPublisher3 = overlay.$isPresented.receive(on: DispatchQueue.main)
        observations.add { [weak self] in
            observedPublisher3.sink { [weak self] presented in
                guard presented, let self else { return }
                self.query = ""
                self.search.stringValue = ""
                self.selectionID = nil
                self.folder = nil
                self.refresh()
                self.scroll.contentView.scroll(to: .zero)
                self.view.window?.makeFirstResponder(self.search)
            }
        }
        let observedPublisher4 = overlay.objectWillChange
        observations.add { [weak self] in
            observedPublisher4.sink { [weak self] in DispatchQueue.main.async { self?.refresh() } }
        }
        observations.add { [weak self] in
            observeChanges { [weak self] in
                guard let self else { return }
                _ = LaunchpadLayoutService.shared.layout
                _ = self.preferences.launchpadBaseIconSize
                _ = self.preferences.launchpadGridColumnCount
                _ = self.preferences.launchpadGridRowCount
                _ = self.preferences.launchpadColumnSpacing
                _ = self.preferences.launchpadSortMode
                _ = self.preferences.launchpadLayoutAxis
                _ = self.preferences.launchpadBackgroundImagePath
                _ = self.preferences.launchpadBackgroundBlursImage
                _ = self.preferences.launchpadOverlayTransparency
                _ = self.overlay.wallpaperURL
                self.refresh()
            }
        }
    }
}
