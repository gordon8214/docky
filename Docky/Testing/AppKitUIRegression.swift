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
            await checkWindowsTaskbar()
            checkWindowSwitcher()
            await checkSwitcherSpaceScope()
            await checkSwitcherHeaderSizes()
            await checkMenuExtras()
            checkMediaTimeline()
            checkDragCancellation()
            checkLaunchpadEditing()
            checkLaunchpadKeyboard()
            checkFolderLifecycle()
            checkWidgetDetails()
            await checkCachedSettings()
            await checkFileBrowser()
            await checkObserverRelease()
            print("AppKit UI integration regressions passed in \(started.duration(to: .now))")
            fflush(stdout)
            exit(0)
        }
        private static func checkSettings() async {
            let suite = RegressionDefaults("settings")
            defer { suite.remove() }
            let settings = SettingsWindowController(defaults: suite.defaults, autosavesFrame: false)
            guard let window = settings.window else { preconditionFailure("Settings needs a window") }
            let root = settings.settings
            precondition(root.selectedPane == .general, "Settings opens on General the first time")
            window.layoutIfNeeded()
            let size = window.frame.size
            for _ in 0..<2 {
                for pane in SettingsPane.allCases {
                    print("Checking settings pane: \(pane.rawValue)")
                    fflush(stdout)
                    precondition(
                        NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: nil) != nil,
                        "\(pane.rawValue) needs a symbol that exists")
                    root.showPane(pane)
                    window.layoutIfNeeded()
                    await Task.yield()
                    precondition(root.splitViewItems.count == 2, "Every pane must retain its sidebar")
                    guard let detail = root.splitViewItems.last?.viewController.view, detail.bounds.width > 0 else {
                        preconditionFailure("\(pane.rawValue) needs a visible detail")
                    }
                    precondition(window.title == pane.title, "The window is titled after \(pane.rawValue)")
                    precondition(
                        window.frame.size == size, "Showing \(pane.rawValue) resized Settings to \(window.frame.size)")
                    precondition(
                        suite.defaults.string(forKey: NativeSettingsController.selectedPaneKey) == pane.rawValue,
                        "Settings remembers the last pane")
                    SettingsLookup.assertUnambiguous(detail, pane.rawValue)
                    for scroll in detail.regressionDescendants(NativeSettingsScrollView.self) {
                        precondition(
                            abs(scroll.form.frame.width - scroll.contentView.bounds.width) < 1,
                            "\(pane.rawValue): the form fills the scroll view's width")
                    }
                }
            }
            precondition(root.canGoBack && !root.canGoForward, "Visiting panes builds back history")
            root.goBack()
            precondition(root.selectedPane == SettingsPane.allCases[SettingsPane.allCases.count - 2])
            precondition(root.canGoForward, "Going back allows going forward")
            root.goForward()
            precondition(root.selectedPane == SettingsPane.allCases.last)
            let reopened = NativeSettingsController(defaults: suite.defaults)
            precondition(reopened.selectedPane == SettingsPane.allCases.last, "Settings reopens on the last pane")
            settings.close()
            await checkLaunchpadInspectorPane()
            captureSettingsSnapshots(suite: suite)
        }

        /// The inspector over Launchpad shows the grid's settings without Availability
        /// or the taskbar tile, which the Settings pane has.
        private static func checkLaunchpadInspectorPane() async {
            let settingsPane = NativeSettingsPaneController(pane: .launchpad)
            _ = settingsPane.view
            let hiddenRows = [String(localized: "Enable Launchpad"), String(localized: "Launchpad Icon")]
            for title in hiddenRows {
                precondition(SettingsLookup.row(title, in: settingsPane.view) != nil, "Settings shows \(title)")
            }
            let pane = NativeSettingsPaneController(pane: .launchpad, placement: .launchpadInspector)
            let window = NSWindow(contentViewController: pane)
            window.isReleasedWhenClosed = false
            window.setContentSize(CGSize(width: 380, height: 520))
            window.layoutIfNeeded()
            await Task.yield()
            precondition(SettingsLookup.row(String(localized: "Grid Columns"), in: pane.view) != nil)
            for title in hiddenRows {
                precondition(SettingsLookup.row(title, in: pane.view) == nil, "The inspector leaves out \(title)")
            }
            SettingsLookup.assertUnambiguous(pane.view, "Launchpad inspector")
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
            let legacy = WidgetCatalog.registration(for: .external("test.legacy.saved"))
            precondition(legacy?.kind == .external("test.legacy.saved"), "Saved tiles preserve external widget kinds")
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
