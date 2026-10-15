import AppKit
import OSLog

extension DockTileInteraction {
    func injectingDockyAppOptions(into actions: [ContextAction], for app: AppTile) -> [ContextAction] {
        var dockyOptions: [ContextAction] = []

        if let showAsWidgetAction = showAsWidgetAction(for: app) {
            dockyOptions.append(showAsWidgetAction)
        }

        if let hideInDockyAction = hideInDockyAction(for: app) {
            if !dockyOptions.isEmpty {
                dockyOptions.append(.divider)
            }
            dockyOptions.append(hideInDockyAction)
        }

        guard !dockyOptions.isEmpty else {
            return actions
        }

        var result = actions
        if let optionsIndex = result.firstIndex(where: {
            $0.kind == .submenu && $0.title == "Options"
        }) {
            var children = result[optionsIndex].children
            if !children.isEmpty, children.last?.kind != .divider {
                children.append(.divider)
            }
            children.append(contentsOf: dockyOptions)
            result[optionsIndex] = .submenu(String(localized: "Options"), children: children)
            return result
        }

        if !result.isEmpty, result.last?.kind != .divider {
            result.append(.divider)
        }
        result.append(.submenu(String(localized: "Options"), children: dockyOptions))
        return result
    }

    func fallbackAppContextActions(
        for app: AppTile,
        modifierFlags: NSEvent.ModifierFlags
    ) -> [ContextAction] {
        let workspace = WorkspaceService.shared
        let isRunning = workspace.isRunning(bundleIdentifier: app.bundleIdentifier)
        let isPinned = tile.id.hasPrefix("pinned:")
        let canTogglePinned = app.bundleIdentifier != Self.finderBundleIdentifier
        let useForceQuit = modifierFlags.contains(.option)
        var actions: [ContextAction] = [
            .action(String(localized: "Open")) {
                workspace.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
            }
        ]

        if isRunning {
            actions.append(
                .action(String(localized: "Show All Windows")) {
                    workspace.showAllWindows(bundleIdentifier: app.bundleIdentifier)
                })
        }

        actions.append(.divider)
        actions.append(
            .submenu(
                String(localized: "Options"),
                children: appOptionsActions(for: app, isPinned: isPinned, canTogglePinned: canTogglePinned)))

        if isDockyPinnedTile || isDockyTrailingTile {
            actions.append(.divider)
            actions.append(
                .action(String(localized: "Remove from Dock")) {
                    removeDockyTile()
                })
        }

        if isRunning && app.bundleIdentifier != Self.finderBundleIdentifier {
            actions.append(.divider)
            actions.append(
                .action(String(localized: "Hide")) {
                    workspace.hide(bundleIdentifier: app.bundleIdentifier)
                })
            actions.append(
                .action(
                    useForceQuit ? "Force Quit" : "Quit",
                    isDestructive: useForceQuit
                ) {
                    workspace.quit(bundleIdentifier: app.bundleIdentifier, force: useForceQuit)
                })
        }

        return actions
    }

    func minimizedWindowContextActions(
        for window: AppWindow,
        modifierFlags _: NSEvent.ModifierFlags
    ) -> [ContextAction] {
        let workspace = WorkspaceService.shared
        return [
            .action(String(localized: "Restore Window")) {
                _ = workspace.restoreMinimizedWindow(window)
            },
            .action(String(localized: "Close Window")) {
                _ = workspace.closeMinimizedWindow(window)
            }
        ]
    }

    func appOptionsActions(
        for app: AppTile,
        isPinned: Bool,
        canTogglePinned: Bool
    ) -> [ContextAction] {
        var actions: [ContextAction] = []

        if canTogglePinned {
            actions.append(
                .action(String(localized: "Keep in Dock"), isOn: isPinned) {
                    _ = TileStore.shared.setPinnedApp(
                        bundleIdentifier: app.bundleIdentifier,
                        pinned: !isPinned
                    )
                })
        }

        if let showAsWidgetAction = showAsWidgetAction(for: app) {
            actions.append(showAsWidgetAction)
        }

        if let hideInDockyAction = hideInDockyAction(for: app) {
            actions.append(hideInDockyAction)
        }

        actions.append(
            .action(FileBrowserService.shared.current.showInTitle) {
                WorkspaceService.shared.revealApplication(bundleIdentifier: app.bundleIdentifier)
            })

        return actions
    }

    func hideInDockyAction(for app: AppTile) -> ContextAction? {
        guard app.bundleIdentifier != Self.finderBundleIdentifier,
            !preferences.isAppHiddenInDocky(bundleIdentifier: app.bundleIdentifier)
        else {
            return nil
        }

        return .action(String(localized: "Hide in Docky")) {
            preferences.setAppHiddenInDocky(bundleIdentifier: app.bundleIdentifier, isHidden: true)
        }
    }

    func showAsWidgetAction(for app: AppTile) -> ContextAction? {
        guard !TileStore.shared.isAppInFolder(bundleIdentifier: app.bundleIdentifier) else {
            return nil
        }

        let candidates = TileStore.shared.appWidgetCandidates(bundleIdentifier: app.bundleIdentifier)
        let configuredDisplay = TileStore.shared.appWidgetDisplay(bundleIdentifier: app.bundleIdentifier)
        let currentKind = configuredDisplay?.kind

        guard !candidates.isEmpty || currentKind != nil else {
            return nil
        }

        var actions: [ContextAction] = [
            .action(String(localized: "App Icon"), isOn: currentKind == nil) {
                TileStore.shared.removeAppWidgetDisplay(bundleIdentifier: app.bundleIdentifier)
            }
        ]

        if !candidates.isEmpty {
            actions.append(.divider)
            actions.append(
                contentsOf: candidates.map { widget in
                    .action(widget.title, isOn: currentKind == widget.kind) {
                        TileStore.shared.setAppWidgetDisplay(
                            bundleIdentifier: app.bundleIdentifier,
                            kind: widget.kind
                        )
                    }
                })
        }

        if let configuredDisplay {
            let availableSpans = availableAppWidgetSpans(for: configuredDisplay.kind)
            if availableSpans.count > 1 {
                actions.append(.divider)
                actions.append(
                    .submenu(
                        String(localized: "Span"),
                        children: availableSpans.map { span in
                            .action(spanTitle(for: span), isOn: configuredDisplay.span == span) {
                                TileStore.shared.setAppWidgetDisplaySpan(
                                    bundleIdentifier: app.bundleIdentifier,
                                    span: span
                                )
                            }
                        }))
            }
        }

        return .submenu(String(localized: "Show as Widget"), children: actions)
    }
}
