import AppKit
import Combine
import QuartzCore

extension MainWindow {
    func handlePointerScreenChangeIfNeeded() {
        guard preferences.windowDisplayTarget == .displayContainingPointer else { return }
        let nextScreenFrame = targetScreen()?.frame
        guard nextScreenFrame != lastPointerScreenFrame else { return }
        lastPointerScreenFrame = nextScreenFrame
        DispatchQueue.main.async { [weak self] in
            self?.applyCurrentFrame(animated: false)
            self?.updateFullscreenStateAndApply(animated: true)
        }
    }

    func pointerDidEnterWindow() {
        if isFullscreenActiveOnTargetScreen, visibilityState == .hidden,
           !revealTriggerZone.contains(NSEvent.mouseLocation) { return }
        isPointerInsideWindow = true
        hideWorkItem?.cancel()

        guard effectivelyAutohides else { return }

        if shouldDwellBeforeReveal {
            scheduleFullscreenReveal()
            return
        }

        fullscreenRevealAuthorized = isFullscreenActiveOnTargetScreen
        setVisibility(.visible, animated: true)
    }

    func pointerDidExitWindow() {
        isPointerInsideWindow = false
        fullscreenRevealWorkItem?.cancel()
        fullscreenRevealWorkItem = nil
        scheduleHideIfNeeded()
    }

    var shouldDwellBeforeReveal: Bool {
        isContentOverlapActive
            && visibilityState == .hidden
            && preferences.fullscreenRevealDelay > 0
    }

    func scheduleFullscreenReveal() {
        fullscreenRevealWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                self.isPointerInsideWindow,
                self.effectivelyAutohides
            else { return }
            self.fullscreenRevealAuthorized = true
            self.setVisibility(.visible, animated: true)
        }
        fullscreenRevealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + preferences.fullscreenRevealDelay, execute: workItem)
    }

    func syncPointerPresence() {
        guard effectivelyAutohides else { return }

        let location = NSEvent.mouseLocation
        let containsPointer = frame.contains(location) || revealTriggerZone.contains(location)
        if containsPointer, !isPointerInsideWindow {
            pointerDidEnterWindow()
        } else if !containsPointer, isPointerInsideWindow {
            pointerDidExitWindow()
        }
    }

    @discardableResult
    func beginInteraction() -> UUID? {
        guard permitsPassivePresentation else { return nil }
        let token = UUID()
        interactionTokens.insert(token)
        hideWorkItem?.cancel()

        if effectivelyAutohides { setVisibility(.visible, animated: true) }
        return token
    }

    func endInteraction(_ token: UUID?) {
        guard let token, interactionTokens.remove(token) != nil else { return }
        scheduleHideIfNeeded()
    }

    func applyEffectiveVisibility(animated: Bool) {
        hideWorkItem?.cancel()

        if effectivelyAutohides {
            let nextState: VisibilityState = shouldRemainVisible ? .visible : .hidden
            setVisibility(nextState, animated: animated)
            return
        }

        setVisibility(.visible, animated: animated)
    }

    func scheduleHideIfNeeded() {
        hideWorkItem?.cancel()

        guard effectivelyAutohides, !shouldRemainVisible else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.shouldRemainVisible else { return }
            self.setVisibility(.hidden, animated: true)
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + preferences.autohideWindowDelay, execute: workItem)
    }

    var shouldRemainVisible: Bool {
        guard permitsPassivePresentation else { return false }
        return isPointerInsideWindow || activeInteractionCount > 0 || editMode.isActive
            || DockDragService.shared.kind != nil
    }

    func setVisibility(_ state: VisibilityState, animated: Bool) {
        if state == .visible, !permitsPassivePresentation { return }
        if state == .visible {
            fullscreenRevealWorkItem?.cancel()
            fullscreenRevealWorkItem = nil
        }

        // Re-requesting the current state must not touch the frame. During a
        // reveal the panel slides under the cursor, the content view's
        // tracking area fires `mouseEntered`, and `pointerDidEnterWindow`
        // asks for `.visible` again while the slide is still in flight. A
        // non-animated `setFrame` here would snap the panel fully on screen,
        // after which the still-running animator reapplies its interpolated
        // (near-hidden) frame and finishes the slide, producing a visible
        // show / hide / show flicker. Layout-input changes already re-apply
        // the frame through their own observers, so nothing is lost by
        // returning early.
        guard visibilityState != state else { return }

        visibilityState = state
        if state == .hidden { fullscreenRevealAuthorized = false }
        NotificationCenter.default.post(name: .dockyVisibilityChanged, object: self)
        applyCurrentFrame(animated: animated)
    }

}
