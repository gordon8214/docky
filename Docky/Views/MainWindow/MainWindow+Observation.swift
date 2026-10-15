import AppKit
import Combine
import QuartzCore

extension MainWindow {
    func observeFrameInputs() {
        // DockyPreferences is now `@Observable` so we read its
        // properties through `observeChanges` (Observation framework
        // auto-tracks). DockSettingsService / DockDragService /
        // DockEditModeService are still ObservableObject; their
        // `@Published` projections are merged via Combine below.
        let layoutSignals: [AnyPublisher<Void, Never>] = [
            editMode.$paletteDrag.map { _ in () }.eraseToAnyPublisher(),
            editMode.$paletteDropDestination.map { _ in () }.eraseToAnyPublisher(),
            DockDragService.shared.$kind.map { _ in () }.eraseToAnyPublisher(),
            DockDragService.shared.$documentTargetTileID.map { _ in () }.eraseToAnyPublisher(),
            DockDragService.shared.$destinationIndex.map { _ in () }.eraseToAnyPublisher(),
            DockDragService.shared.$destinationSection.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(layoutSignals)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentFrame(animated: true, duration: self?.tileMutationAnimationDuration)
            }
            .store(in: &cancellables)

        observeChanges { [weak self] in
            guard let self else { return }
            // Touch every preference and dock-setting that drives frame
            // layout. The Observation framework tracks these reads and
            // re-runs the closure on any change.
            _ = preferences.effectiveTileVerticalPadding
            _ = preferences.effectiveTileSpacing
            _ = preferences.overflowBehavior
            _ = preferences.effectiveWindowAxisSizing
            _ = preferences.effectiveWindowContentInsetTop
            _ = preferences.effectiveWindowContentInsetBottom
            _ = preferences.effectiveWindowContentInsetLeading
            _ = preferences.effectiveWindowContentInsetTrailing
            _ = preferences.windowPosition
            _ = preferences.windowDisplayTarget
            _ = dockSettings.orientation
            _ = dockSettings.tileSize
            _ = dockSettings.largeSize
            _ = dockSettings.magnification
            _ = preferences.windowsTaskbarHeight
            self.applyCurrentFrame(animated: true, duration: self.tileMutationAnimationDuration)
        }
        .store(in: &cancellables)

        observeTileAndInteractionInputs()
    }

    func observeTileAndInteractionInputs() {
        tileStore.$tiles
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentFrame(animated: true, duration: self?.tileMutationAnimationDuration)
            }
            .store(in: &cancellables)

        editMode.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                guard let self else { return }
                if isActive, self.permitsPassivePresentation {
                    self.hideWorkItem?.cancel()
                    self.setVisibility(.visible, animated: true)
                } else {
                    self.scheduleHideIfNeeded()
                }
            }
            .store(in: &cancellables)

        // Keep the dock visible while any drag is in flight (Finder→dock,
        // palette, or icon-out-of-folder). The cursor can briefly be outside
        // the dock window during the transit, so without this the dock would
        // start to auto-hide just as the user is moving the drag toward it.
        DockDragService.shared.$kind
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasDrag in
                guard let self else { return }
                if hasDrag, self.permitsPassivePresentation {
                    self.hideWorkItem?.cancel()
                    self.setVisibility(.visible, animated: true)
                } else {
                    self.scheduleHideIfNeeded()
                }
            }
            .store(in: &cancellables)

    }

    func observeScreenAndSpaceInputs() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentFrame(animated: false)
                self?.updateFullscreenStateAndApply(animated: false)
            }
            .store(in: &cancellables)

        let workspaceCenter = NSWorkspace.shared.notificationCenter

        workspaceCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentFrame(animated: false)
                self?.updateFullscreenStateAndApply(animated: true)
                // The space change fires during the fullscreen exit animation
                // while the fullscreen window is still on-screen. Re-check once
                // the animation has had time to complete.
                self?.scheduleFullscreenRecheck()
            }
            .store(in: &cancellables)

        workspaceCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFullscreenStateAndApply(animated: true)
                self?.scheduleFullscreenRecheck()
            }
            .store(in: &cancellables)
    }

    func observeWindowPlacementInputs() {
        observeChanges { [weak self] in
            _ = DockyPreferences.shared.windowSpaceBehavior
            self?.applyCollectionBehavior()
        }
        .store(in: &cancellables)

        observeChanges { [weak self] in
            _ = DockyPreferences.shared.windowDisplayTarget
            self?.lastPointerScreenFrame = nil
            self?.updatePointerScreenMonitoring()
            self?.updateFullscreenStateAndApply(animated: true)
        }
        .store(in: &cancellables)

        PermissionsService.shared.$accessibility
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.lastPointerScreenFrame = nil
                self?.updatePointerScreenMonitoring()
            }
            .store(in: &cancellables)

        // App-level activate/space changes don't fire when a window in the
        // foreground app gets maximized or fullscreened, so piggy-back on the
        // registry's AX resize/move signal. Debounce so a drag-resize doesn't
        // hammer the overlap recomputation.
        WindowRegistry.shared.$windows
            .debounce(for: .milliseconds(80), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFullscreenStateAndApply(animated: true)
            }
            .store(in: &cancellables)
    }

    func observeVisibilityInputs() {
        observeChanges { [weak self] in
            _ = DockyPreferences.shared.autohidesWindow
            guard let self else { return }
            let previous = self.visibilityState
            self.applyEffectiveVisibility(animated: true)
            // An autohide preference change releases reservation even if a
            // hover keeps the current window visible.
            if previous == self.visibilityState { self.applyCurrentFrame(animated: false) }
        }
        .store(in: &cancellables)

    }

    func applyCollectionBehavior() {
        collectionBehavior = preferences.windowSpaceBehavior.collectionBehavior(includesFullScreenAuxiliary: true)
    }

    func updatePointerScreenMonitoring() {
        if let globalPointerMonitor {
            NSEvent.removeMonitor(globalPointerMonitor)
            self.globalPointerMonitor = nil
        }
        if let localPointerMonitor {
            NSEvent.removeMonitor(localPointerMonitor)
            self.localPointerMonitor = nil
        }

        guard preferences.windowDisplayTarget == .displayContainingPointer else { return }

        let pointerEvents: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel
        ]
        if PermissionsService.shared.accessibility == .granted {
            globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: pointerEvents) { [weak self] _ in
                self?.handlePointerScreenChangeIfNeeded()
            }
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: pointerEvents) { [weak self] event in
            self?.handlePointerScreenChangeIfNeeded()
            return event
        }
    }

    /// A hidden panel sits off-screen, where its tracking area can't fire, so
    /// the reveal runs off monitored pointer movement instead.
    func updateRevealMonitoring() {
        if let globalDragRevealMonitor {
            NSEvent.removeMonitor(globalDragRevealMonitor)
            self.globalDragRevealMonitor = nil
        }
        if let localDragRevealMonitor {
            NSEvent.removeMonitor(localDragRevealMonitor)
            self.localDragRevealMonitor = nil
        }

        let revealEvents: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged
        ]
        globalDragRevealMonitor = NSEvent.addGlobalMonitorForEvents(matching: revealEvents) { [weak self] _ in
            self?.syncPointerPresence()
        }
        localDragRevealMonitor = NSEvent.addLocalMonitorForEvents(matching: revealEvents) { [weak self] event in
            self?.syncPointerPresence()
            return event
        }
    }

}
