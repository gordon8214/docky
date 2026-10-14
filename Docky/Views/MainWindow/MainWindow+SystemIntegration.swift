import AppKit
import Combine
import QuartzCore

extension MainWindow {
    func didOrderDockWindow() {
        updateFullscreenStateAndApply(animated: false)
        applyCurrentFrame(animated: false)
    }

    func refreshSystemIntegration() {
        updateFullscreenStateAndApply(animated: false)
        handlePointerScreenChangeIfNeeded()
        syncPointerPresence()
    }

    func updateFullscreenStateAndApply(animated: Bool) {
        let next = computeContentOverlapStateOnTargetScreen().isFullscreen
        applyFullscreenState(next, animated: animated)
    }

    func applyFullscreenState(_ next: Bool, animated: Bool) {
        guard next != isFullscreenActiveOnTargetScreen else { return }
        isFullscreenActiveOnTargetScreen = next
        fullscreenRevealAuthorized = false
        isPointerInsideWindow = false
        interactionTokens.removeAll()
        hideWorkItem?.cancel()
        fullscreenRevealWorkItem?.cancel()
        if next {
            setSearchFocus(false)
            WindowPreviewWindowController.shared.dismissImmediately()
            WidgetExpansionWindowController.shared.dismissImmediately()
            WidgetSettingsPanelController.shared.dismiss()
            editMode.exit()
            DockDragService.shared.clear()
            dismissAttachedViews(in: contentView)
            NotificationCenter.default.post(name: .dockyEnteredFullscreen, object: self)
            // Fullscreen entry must ignore stale hover and interaction holds.
            setVisibility(.hidden, animated: false)
            applyCurrentFrame(animated: false)
        } else {
            applyEffectiveVisibility(animated: animated)
        }
    }

    func dismissAttachedViews(in view: NSView?) {
        guard let view else { return }
        (view as? NativeDockTileView)?.dismissTransientPresentation()
        for child in view.subviews { dismissAttachedViews(in: child) }
    }

    func scheduleFullscreenRecheck() {
        fullscreenRecheckWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.updateFullscreenStateAndApply(animated: true) }
        fullscreenRecheckWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: workItem)
    }

    struct ContentOverlapObservation { let isFullscreen: Bool }

    func computeContentOverlapStateOnTargetScreen() -> ContentOverlapObservation {
        guard let screen = targetScreen() else { return ContentOverlapObservation(isFullscreen: false) }
        // A failed Space query preserves the last state during transitions;
        // it must never reveal Docky on the basis of missing AX permission.
        return ContentOverlapObservation(
            isFullscreen: NativeDockIntegration.isFullscreen(screen) ?? isFullscreenActiveOnTargetScreen)
    }
}

extension Notification.Name {
    static let dockyVisibilityChanged = Notification.Name("DockyVisibilityChanged")
    static let dockyEnteredFullscreen = Notification.Name("DockyEnteredFullscreen")
}
