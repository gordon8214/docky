import AppKit
import OSLog

extension DockTileInteraction {
    func widgetContextActions(for widget: WidgetTile) -> [ContextAction] {
        let builders: [String: (WidgetTile) -> [ContextAction]] = [
            "calendar": calendarWidgetActions,
            "calendarDate": calendarDateWidgetActions,
            "reminders": remindersWidgetActions,
            "batteries": batteriesWidgetActions,
            "systemStatus": systemStatusWidgetActions,
            "nowPlaying": nowPlayingWidgetActions,
            "weather": weatherWidgetActions,
            "search": searchWidgetActions,
            "photoFrame": photoFrameWidgetActions
        ]
        return (builders[widget.kind.rawValue] ?? externalWidgetActions)(widget)
    }
    /// Only pinned/trailing widgets carry per-instance identity, so only they get settings.
    func widgetSettingsAction(for widget: WidgetTile) -> ContextAction? {
        guard isDockyPinnedTile || isDockyTrailingTile else {
            return nil
        }
        guard widget.kind.hasConfigurableSettings else {
            return nil
        }

        return .action(String(localized: "Widget Settings…")) {
            WidgetSettingsPanelController.shared.present(
                widget: widget,
                tileID: tile.id,
                sourceFrame: globalTileFrame
            )
        }
    }

    func widgetSpanMenuAction(for widget: WidgetTile) -> ContextAction? {
        guard isDockyPinnedTile || isDockyTrailingTile else {
            return nil
        }

        let availableSpans = availableWidgetSpans(for: widget)
        guard availableSpans.count > 1 else {
            return nil
        }

        return .submenu(
            String(localized: "Span"),
            children: availableSpans.map { span in
                ContextAction.action(spanTitle(for: span), isOn: widget.span == span) {
                    applyWidgetSpan(span)
                }
            })
    }

    func availableWidgetSpans(for widget: WidgetTile) -> [TileSpan] {
        if position.isVertical {
            return [.one]
        }

        return widget.kind.supportedSpans.filter { $0 != .four }
    }

    func availableAppWidgetSpans(for kind: WidgetKind) -> [TileSpan] {
        if position.isVertical {
            return [.one]
        }

        return kind.supportedSpans.filter { $0 != .four }
    }

    func applyWidgetSpan(_ span: TileSpan) {
        if isDockyPinnedTile {
            TileStore.shared.setPinnedWidgetSpan(tileID: tile.id, span: span)
        } else if isDockyTrailingTile {
            TileStore.shared.setTrailingWidgetSpan(tileID: tile.id, span: span)
        }
    }

    func widgetRemovalAction(for widget: WidgetTile, nonDockyTitle: String = "Remove Widget") -> ContextAction {
        if isDockyPinnedTile || isDockyTrailingTile {
            return .action(String(localized: "Remove from Dock")) {
                removeDockyTile()
            }
        }

        return .action(nonDockyTitle) {
            TileStore.shared.removeWidget(
                kind: widget.kind,
                ownerBundleIdentifier: widget.settings.string("nowPlaying.appBundleIdentifier")
                    ?? widget.ownerBundleIdentifier
            )
        }
    }

    func appendDividerIfNeeded(to actions: inout [ContextAction]) {
        guard !actions.isEmpty, actions.last?.kind != .divider else {
            return
        }

        actions.append(.divider)
    }

    func reminderCompletionTitle(for item: ReminderItemSnapshot, now: Date) -> String {
        let detail = reminderCompletionDetail(for: item, now: now)
        return detail.isEmpty ? item.title : "\(item.title) - \(detail)"
    }

    func reminderCompletionDetail(for item: ReminderItemSnapshot, now: Date) -> String {
        switch item.timingCategory(relativeTo: now) {
        case .overdue:
            return "overdue"
        case .today:
            return "today"
        case .upcoming:
            return "upcoming"
        case .unscheduled:
            return item.listTitle
        }
    }

    func smartStackContextActions(for stack: SmartStackTile) -> [ContextAction] {
        var actions: [ContextAction] = []
        let widgetVisibilityActions = TileStore.shared.smartStackWidgetCandidates(tileID: tile.id).map { widget in
            ContextAction.action(
                widget.title,
                isOn: TileStore.shared.isSmartStackWidgetVisible(
                    tileID: tile.id,
                    ownerBundleIdentifier: widget.settings.string("nowPlaying.appBundleIdentifier")
                        ?? widget.ownerBundleIdentifier
                )
            ) {
                let isVisible = TileStore.shared.isSmartStackWidgetVisible(
                    tileID: tile.id,
                    ownerBundleIdentifier: widget.settings.string("nowPlaying.appBundleIdentifier")
                        ?? widget.ownerBundleIdentifier
                )
                TileStore.shared.setSmartStackWidgetVisibility(
                    tileID: tile.id,
                    ownerBundleIdentifier: widget.settings.string("nowPlaying.appBundleIdentifier")
                        ?? widget.ownerBundleIdentifier,
                    isVisible: !isVisible
                )
            }
        }

        if !widgetVisibilityActions.isEmpty {
            actions.append(.submenu(String(localized: "Widgets"), children: widgetVisibilityActions))
        }

        if isDockyPinnedTile || isDockyTrailingTile {
            if !actions.isEmpty {
                actions.append(.divider)
            }
            actions.append(
                .action(String(localized: "Edit Dock...")) {
                    DockEditModeService.shared.enter()
                })
            actions.append(
                .action(String(localized: "Remove from Dock")) {
                    removeDockyTile()
                })
        }

        return actions
    }
    func handleWidgetTap(_ widget: WidgetTile) {
        let actions: [String: () -> Void] = [
            "calendar": { workspace.activateOrOpen(bundleIdentifier: WidgetOwnerBundleIdentifiers.calendar) },
            "calendarDate": { workspace.activateOrOpen(bundleIdentifier: WidgetOwnerBundleIdentifiers.calendar) },
            "reminders": { workspace.activateOrOpen(bundleIdentifier: WidgetOwnerBundleIdentifiers.reminders) },
            "batteries": { BatteriesService.shared.openInBatterySettings() },
            "systemStatus": { SystemStatusService.shared.openInActivityMonitor() },
            "nowPlaying": {
                Task {
                    await mediaPlayback.togglePlayPause(
                        for: widget.settings.string("nowPlaying.appBundleIdentifier") ?? widget.ownerBundleIdentifier)
                }
            },
            "weather": { WeatherService.shared.openInWeatherApp() },
            "search": { tapSearch(widget) }, "photoFrame": tapPhotoFrame
        ]
        actions[widget.kind.rawValue]?()
    }
    func tapSearch(_ widget: WidgetTile) {
        if widget.effectiveSpan == .one, let url = URL(string: "https://www.google.com") {
            NSWorkspace.shared.open(url)
        }
    }
    func tapPhotoFrame() {
        if PhotoFrameService.shared.hasPhotos {
            PhotoFrameService.shared.advance()
        } else {
            PhotoFrameService.shared.choosePhotos()
        }
    }

    func spanTitle(for span: TileSpan) -> String {
        switch span {
        case .one:
            "1 Tile"
        case .two:
            "2 Tiles"
        case .three:
            "3 Tiles"
        case .four:
            "4 Tiles"
        }
    }
}
