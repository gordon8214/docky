import AppKit

extension DockTileInteraction {
    func calendarWidgetActions(_ widget: WidgetTile) -> [ContextAction] {
        var actions: [ContextAction] = []

        if let quickJoinURL = CalendarService.shared.nextEvent?.quickJoinURL {
            actions.append(
                .action(String(localized: "Quick Join")) {
                    NSWorkspace.shared.open(quickJoinURL)
                })
        }

        if let spanMenuAction = widgetSpanMenuAction(for: widget) {
            appendDividerIfNeeded(to: &actions)
            actions.append(spanMenuAction)
        }

        appendDividerIfNeeded(to: &actions)
        actions.append(
            .action(String(localized: "Refresh Calendar")) {
                CalendarService.shared.refresh(force: true)
            })
        actions.append(.divider)
        actions.append(
            .action(String(localized: "Open Calendar")) {
                WorkspaceService.shared.activateOrOpen(bundleIdentifier: WidgetOwnerBundleIdentifiers.calendar)
            })
        if let settingsAction = widgetSettingsAction(for: widget) {
            actions.append(.divider)
            actions.append(settingsAction)
        }
        actions.append(.divider)
        actions.append(widgetRemovalAction(for: widget))
        return actions
    }

    func calendarDateWidgetActions(_ widget: WidgetTile) -> [ContextAction] {
        return [
            .action(String(localized: "Open Calendar")) {
                WorkspaceService.shared.activateOrOpen(bundleIdentifier: WidgetOwnerBundleIdentifiers.calendar)
            },
            .divider,
            widgetRemovalAction(for: widget)
        ]
    }

    func remindersWidgetActions(_ widget: WidgetTile) -> [ContextAction] {
        var actions: [ContextAction] = []

        let completionActions =
            RemindersService.shared.snapshot?.completionCandidates.map { item in
                ContextAction.action(reminderCompletionTitle(for: item, now: Date())) {
                    Task {
                        _ = await RemindersService.shared.completeReminder(identifier: item.identifier)
                    }
                }
            } ?? []

        if !completionActions.isEmpty {
            actions.append(.submenu(String(localized: "Complete"), children: completionActions))
        }

        if let spanMenuAction = widgetSpanMenuAction(for: widget) {
            appendDividerIfNeeded(to: &actions)
            actions.append(spanMenuAction)
        }

        appendDividerIfNeeded(to: &actions)
        actions.append(
            .action(String(localized: "Refresh Reminders")) {
                RemindersService.shared.refresh(force: true)
            })
        actions.append(.divider)
        actions.append(
            .action(String(localized: "Open Reminders")) {
                WorkspaceService.shared.activateOrOpen(bundleIdentifier: WidgetOwnerBundleIdentifiers.reminders)
            })
        actions.append(.divider)
        actions.append(widgetRemovalAction(for: widget))
        return actions
    }

    func batteriesWidgetActions(_ widget: WidgetTile) -> [ContextAction] {
        var actions: [ContextAction] = [
            .action(String(localized: "Refresh Batteries")) {
                BatteriesService.shared.refresh(force: true)
            }
        ]

        if let spanMenuAction = widgetSpanMenuAction(for: widget) {
            actions.append(.divider)
            actions.append(spanMenuAction)
        }

        actions.append(.divider)
        actions.append(
            .action(String(localized: "Open Battery Settings")) {
                BatteriesService.shared.openInBatterySettings()
            })
        actions.append(.divider)
        actions.append(widgetRemovalAction(for: widget))
        return actions
    }

    func systemStatusWidgetActions(_ widget: WidgetTile) -> [ContextAction] {
        var actions: [ContextAction] = [
            .action(String(localized: "Refresh Status")) {
                SystemStatusService.shared.refresh(force: true)
            }
        ]

        if let spanMenuAction = widgetSpanMenuAction(for: widget) {
            actions.append(.divider)
            actions.append(spanMenuAction)
        }

        actions.append(.divider)
        actions.append(
            .action(String(localized: "Open Activity Monitor")) {
                SystemStatusService.shared.openInActivityMonitor()
            })
        actions.append(.divider)
        actions.append(widgetRemovalAction(for: widget))
        return actions
    }

    func nowPlayingWidgetActions(_ widget: WidgetTile) -> [ContextAction] {
        var actions: [ContextAction] = []

        if let bundleIdentifier = mediaPlayback.resolvedBundleIdentifier(
            for: widget.settings.string("nowPlaying.appBundleIdentifier") ?? widget.ownerBundleIdentifier) {
            actions.append(
                .action(String(localized: "Open App")) {
                    WorkspaceService.shared.activateOrOpen(bundleIdentifier: bundleIdentifier)
                })
            actions.append(.divider)
        }

        actions.append(contentsOf: mediaTransportActions(widget))

        if let playbackState = mediaPlayback.state(
            for: widget.settings.string("nowPlaying.appBundleIdentifier") ?? widget.ownerBundleIdentifier),
            playbackState.supportsFavorite {
            actions.append(
                .action(playbackState.isFavorite ? "Unfavorite" : "Favorite") {
                    Task {
                        await mediaPlayback.setFavorite(
                            !playbackState.isFavorite,
                            for: widget.settings.string("nowPlaying.appBundleIdentifier")
                                ?? widget.ownerBundleIdentifier)
                    }
                })
        }

        if let spanMenuAction = widgetSpanMenuAction(for: widget) {
            actions.append(.divider)
            actions.append(spanMenuAction)
        }

        if let settingsAction = widgetSettingsAction(for: widget) {
            actions.append(.divider)
            actions.append(settingsAction)
        }
        actions.append(.divider)
        actions.append(widgetRemovalAction(for: widget, nonDockyTitle: "Remove Stack"))
        return actions
    }

    func mediaTransportActions(_ widget: WidgetTile) -> [ContextAction] {
        return [
            .action(String(localized: "Play/Pause")) {
                Task {
                    await mediaPlayback.togglePlayPause(
                        for: widget.settings.string("nowPlaying.appBundleIdentifier")
                            ?? widget.ownerBundleIdentifier)
                }
            },
            .action(String(localized: "Previous Track")) {
                Task {
                    await mediaPlayback.skipToPrevious(
                        for: widget.settings.string("nowPlaying.appBundleIdentifier")
                            ?? widget.ownerBundleIdentifier)
                }
            },
            .action(String(localized: "Next Track")) {
                Task {
                    await mediaPlayback.skipToNext(
                        for: widget.settings.string("nowPlaying.appBundleIdentifier")
                            ?? widget.ownerBundleIdentifier)
                }
            }
        ]
    }

    func weatherWidgetActions(_ widget: WidgetTile) -> [ContextAction] {
        var actions: [ContextAction] = [
            .action(String(localized: "Refresh Weather")) {
                WeatherService.shared.refresh(force: true)
            }
        ]

        if let spanMenuAction = widgetSpanMenuAction(for: widget) {
            actions.append(.divider)
            actions.append(spanMenuAction)
        }

        actions.append(.divider)
        actions.append(
            .action(String(localized: "Open Weather")) {
                WeatherService.shared.openInWeatherApp()
            })
        if let settingsAction = widgetSettingsAction(for: widget) {
            actions.append(.divider)
            actions.append(settingsAction)
        }
        actions.append(.divider)
        actions.append(widgetRemovalAction(for: widget))
        return actions
    }

    func searchWidgetActions(_ widget: WidgetTile) -> [ContextAction] {
        var actions: [ContextAction] = []
        if let spanMenuAction = widgetSpanMenuAction(for: widget) {
            actions.append(spanMenuAction)
            actions.append(.divider)
        }
        actions.append(
            .action(String(localized: "Open Google")) {
                if let url = URL(string: "https://www.google.com") {
                    NSWorkspace.shared.open(url)
                }
            })
        actions.append(.divider)
        actions.append(widgetRemovalAction(for: widget))
        return actions
    }

    func photoFrameWidgetActions(_ widget: WidgetTile) -> [ContextAction] {
        var actions: [ContextAction] = [
            .action(String(localized: "Choose Photos…")) {
                PhotoFrameService.shared.choosePhotos()
            }
        ]

        if PhotoFrameService.shared.hasPhotos {
            if PhotoFrameService.shared.photoCount > 1 {
                actions.append(
                    .action(String(localized: "Next Photo")) {
                        PhotoFrameService.shared.advance()
                    })
            }
            actions.append(
                .action(String(localized: "Clear Photos")) {
                    PhotoFrameService.shared.clearPhotos()
                })
        }

        if let spanMenuAction = widgetSpanMenuAction(for: widget) {
            actions.append(.divider)
            actions.append(spanMenuAction)
        }

        actions.append(.divider)
        actions.append(widgetRemovalAction(for: widget))
        return actions
    }

    func externalWidgetActions(_ widget: WidgetTile) -> [ContextAction] {
        var actions: [ContextAction] = []
        if let spanMenuAction = widgetSpanMenuAction(for: widget) {
            actions.append(spanMenuAction)
            actions.append(.divider)
        }
        if let settingsAction = widgetSettingsAction(for: widget) {
            actions.append(settingsAction)
            actions.append(.divider)
        }
        actions.append(widgetRemovalAction(for: widget))
        return actions
    }
}
