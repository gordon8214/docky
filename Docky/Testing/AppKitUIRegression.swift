#if DEBUG
    import AppKit
    import Darwin

    /// Bounded integration coverage against the actual compiled native controllers.
    @MainActor
    enum AppKitUIRegression {
        static func run() async {
            let started = ContinuousClock.now
            await checkSettings()
            checkWidgets()
            await checkThemeWidgetRemoval()
            await checkWindowsTaskbar()
            checkWindowSwitcher()
            await checkMenuExtras()
            checkMediaTimeline()
            checkDragCancellation()
            checkLaunchpadEditing()
            checkLaunchpadKeyboard()
            checkFolderLifecycle()
            checkWidgetDetails()
            await checkCachedSettings()
            await checkObserverRelease()
            print("AppKit UI integration regressions passed in \(started.duration(to: .now))")
            fflush(stdout)
            exit(0)
        }
        private static func checkSettings() async {
            let root = NativeSettingsController()
            let window = NSWindow(contentViewController: root)
            window.isReleasedWhenClosed = false
            window.setContentSize(CGSize(width: 820, height: 540))
            for _ in 0..<2 {
                for pane in NativeSettingsController.panes {
                    print("Checking settings pane: \(pane.id)")
                    fflush(stdout)
                    root.showPane(pane.id)
                    window.layoutIfNeeded()
                    await Task.yield()
                    precondition(root.splitViewItems.count == 2, "Every pane must retain its sidebar")
                    precondition(root.splitViewItems.last?.viewController.view.bounds.width ?? 0 > 0)
                }
            }
            window.contentViewController = nil
            window.close()
        }
        private static func checkWidgets() {
            let registrations =
                WidgetCatalog.builtInRegistrations + [
                    WidgetRegistration(
                        kind: .external("test.legacy"),
                        ownerBundleIdentifier: "test.legacy", defaultSpan: .three, includesInPalette: false,
                        includesInSmartStack: true)
                ]
            let legacy = WidgetCatalog.registration(for: .external("test.legacy.theme"))
            precondition(legacy?.kind == .external("test.legacy.theme"), "Theme insertions preserve external kinds")
            precondition(legacy?.includesInPalette == false && legacy?.includesInSmartStack == false)
            let root = NSView(frame: CGRect(x: 0, y: 0, width: 500, height: 400))
            let window = NSWindow(contentRect: root.frame, styleMask: [], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = root
            for registration in registrations {
                for span in registration.kind.supportedSpans.filter({ $0 != .four }) {
                    for expanded in [false, true] {
                        print(
                            "Checking widget: \(registration.kind.rawValue), "
                                + "span: \(span.rawValue), expanded: \(expanded)"
                        )
                        fflush(stdout)
                        let widget = NativeWidgetView(
                            tile: registration.makeTile(span: span), cornerRadius: 8, span: span, expanded: expanded)
                        widget.frame = CGRect(
                            x: 0, y: 0, width: expanded ? 380 : CGFloat(span.rawValue) * 60,
                            height: expanded ? 320 : 60)
                        root.addSubview(widget)
                        root.layoutSubtreeIfNeeded()
                        precondition(
                            !widget.stack.arrangedSubviews.isEmpty, "Every widget needs content or a permission state")
                        widget.removeFromSuperview()
                        precondition(widget.subscriptions.isEmpty, "Detached widgets must cancel their observers")
                    }
                }
            }
            let stack = NativeSmartStackView(
                tile: SmartStackTile(
                    identifier: "test", title: "Smart Stack",
                    widgets: [registrations[0].makeTile(), registrations[registrations.count - 1].makeTile()],
                    span: .three),
                cornerRadius: 8, span: .three)
            root.addSubview(stack)
            stack.frame = root.bounds
            stack.cycle(1)
            stack.cycle(-1)
            root.layoutSubtreeIfNeeded()
            window.contentView = nil
            window.close()
        }
        private static func checkMediaTimeline() {
            let state = MediaPlaybackState(
                bundleIdentifier: "test.media", displayName: "Test Media", title: "Track", artist: "Artist",
                album: "Album",
                currentTime: 80, duration: 120, isPlaying: false, isAvailable: true,
                supportsFavorite: false, isFavorite: false, artworkData: nil, lastUpdated: Date())
            let lyrics = LyricsContent(
                plain: "Lyrics", lines: (0..<20).map { SyncedLyricsLine(time: Double($0 * 5), text: "Line \($0)") })
            let widget = NativeWidgetView(
                tile: WidgetCatalog.genericNowPlaying.makeTile(), cornerRadius: 8, span: .three, expanded: true)
            widget.clear()
            let clock = NativeMediaPlaybackTimeline(state: state)
            let synced = NativeMediaPlaybackTimeline(state: state, lyrics: lyrics)
            widget.add(clock)
            widget.add(synced)
            widget.frame = CGRect(x: 0, y: 0, width: 380, height: 320)
            widget.layoutSubtreeIfNeeded()
            precondition(
                clock.frame.width > 300 && synced.frame.width > 300,
                "Playback timelines must fill the widget's width")
            precondition(synced.scroll.contentView.bounds.minY > 0, "Lyrics must initially reveal the current line")
        }
        private static func checkDragCancellation() {
            let canvas = DockCanvasView()
            canvas.frame = CGRect(x: 0, y: 0, width: 600, height: 80)
            let tile = Tile(
                id: "pinned:test", content: .app(AppTile(bundleIdentifier: "com.apple.finder", displayName: "Finder")))
            let view = NativeDockTileView(tile: tile)
            view.canvas = canvas
            canvas.addSubview(view)
            view.mouseDownPoint = CGPoint(x: 20, y: 20)
            view.wasDragging = true
            canvas.controller.draggedTileID = tile.id
            view.cancelDrag()
            canvas.cancelDrag()
            precondition(view.canceledMouseSession && !view.wasDragging && view.mouseDownPoint == nil)
            canvas.controller.endDrag(for: tile, value: DockPointerDrag(location: .zero, translation: .zero))
            precondition(
                canvas.controller.draggedTileID == nil, "Mouse-up after Escape must not restart a canceled drag")
            view.removeFromSuperview()
        }
        private static func checkObserverRelease() async {
            weak var released: NativeWidgetView?
            autoreleasepool {
                let view = NativeWidgetView(tile: WidgetCatalog.calendar.makeTile(), cornerRadius: 8, span: .three)
                released = view
            }
            await Task.yield()
            precondition(released == nil, "Widget subscriptions must not retain a released view")
        }
    }
#endif
