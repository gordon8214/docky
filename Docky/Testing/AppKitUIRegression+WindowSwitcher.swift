#if DEBUG
    import AppKit

    /// Builds the Windows 11–style switcher from fixture cards, so it runs
    /// without live windows or capture permission.
    extension AppKitUIRegression {
        static func checkWindowSwitcher() {
            print("Checking window switcher")
            fflush(stdout)
            let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
            let controller = WindowSwitcherController()
            let window = NSWindow(contentRect: screen, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            window.setContentSize(screen.size)
            controller.view.layoutSubtreeIfNeeded()

            let cards = switcherFixtureCards()
            controller.display(cards: cards, selectedID: cards[1].id)
            controller.view.layoutSubtreeIfNeeded()

            guard let geometry = controller.geometry else { preconditionFailure("Cards need a layout") }
            precondition(controller.cardViews.count == cards.count, "Every window gets a card")
            precondition(geometry.rows.count == 2, "Seven fixture cards wrap into two rows")
            let panel = controller.panelView.frame
            precondition(panel.size == geometry.panelSize, "The panel hugs its cards")
            precondition(abs(panel.midX - screen.midX) <= 0.5 && abs(panel.midY - screen.midY) <= 0.5,
                         "The panel is centered on the screen")
            for (index, card) in cards.enumerated() {
                precondition(
                    controller.cardViews[card.id]?.frame == geometry.cardFrames[index],
                    "Cards follow the switcher geometry")
            }
            precondition(controller.cardViews[cards[1].id]?.isSelected == true, "The selected card is framed")
            precondition(controller.cardViews.values.filter(\.isSelected).count == 1, "Only one card is framed")
            precondition(controller.cardViews[cards[3].id]?.showsFallbackIcon == true,
                         "Windows without a capture show their app icon")
            precondition(controller.cardViews[cards[0].id]?.showsFallbackIcon == false)

            guard let hovered = controller.cardViews[cards[2].id] else { preconditionFailure("Card required") }
            precondition(hovered.closeButton.isHidden, "The close button only appears on hover")
            hovered.setHovered(true)
            precondition(!hovered.closeButton.isHidden, "Hovering a card shows its close button")
            hovered.setHovered(false)
            precondition(hovered.closeButton.isHidden)

            let lastRowCard = geometry.rows[1][0]
            let neighbor = WindowSwitcherService.shared.verticalNeighbor?(cards[lastRowCard].id, -1)
            precondition(
                neighbor == geometry.neighbor(of: lastRowCard, direction: -1).map { cards[$0].id },
                "Up and down follow the rows on screen")

            let reused = controller.cardViews[cards[0].id]
            controller.display(cards: cards, selectedID: cards[4].id)
            precondition(controller.cardViews[cards[0].id] === reused, "Selection changes reuse card views")
            precondition(controller.cardViews[cards[4].id]?.isSelected == true)
            precondition(controller.cardViews[cards[1].id]?.isSelected == false)

            captureSwitcherSnapshots(controller.view)

            controller.display(cards: Array(cards.dropLast()), selectedID: cards[0].id)
            precondition(controller.cardViews[cards[6].id] == nil, "Closed windows lose their cards")
            controller.display(cards: [], selectedID: nil)
            controller.view.layoutSubtreeIfNeeded()
            precondition(controller.cardViews.isEmpty)
            precondition(controller.panelView.frame.size == WindowSwitcherController.emptyPanelSize,
                         "No windows shows the empty panel")

            window.contentViewController = nil
            window.close()
        }

        private static func switcherFixtureCards() -> [WindowSwitcherCard] {
            let apps: [(String, String, String, CGFloat?)] = [
                ("com.apple.Safari", "Safari", "Apple — Start Page", 16.0 / 10.0),
                ("com.apple.finder", "Finder", "Downloads", 4.0 / 3.0),
                ("com.apple.Terminal", "Terminal", "gordon — zsh — 120×40", 16.0 / 10.0),
                ("com.apple.Notes", "Notes", "Shopping list", nil),
                ("com.apple.mail", "Mail", "Inbox — 3 unread messages in a very long mailbox title", 16.0 / 9.0),
                ("com.apple.Music", "Music", "Library", 2.4),
                ("com.apple.Preview", "Preview", "Receipt.pdf", 0.7),
            ]
            let colors: [NSColor] = [.systemBlue, .systemGray, .black, .systemYellow, .systemTeal, .systemPink, .white]
            return apps.enumerated().map { index, app in
                let (bundleID, name, title, aspect) = app
                let thumbnail = aspect.map { fixtureThumbnail(aspectRatio: $0, color: colors[index]) }
                return WindowSwitcherCard(
                    id: "fixture-\(index)", title: title, appName: name,
                    icon: IconCacheService.shared.icon(forBundleIdentifier: bundleID),
                    thumbnail: thumbnail,
                    aspectRatio: WindowSwitcherController.aspectRatio(thumbnail: thumbnail, frame: nil))
            }
        }

        /// A window-shaped picture: a title bar over a colored body.
        private static func fixtureThumbnail(aspectRatio: CGFloat, color: NSColor) -> NSImage {
            let size = CGSize(width: 300 * aspectRatio, height: 300)
            return NSImage(size: size, flipped: true) { rect in
                color.setFill()
                rect.fill()
                NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
                CGRect(x: 0, y: 0, width: rect.width, height: 28).fill()
                for (offset, dot) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                    dot.setFill()
                    NSBezierPath(ovalIn: CGRect(x: 10 + CGFloat(offset) * 18, y: 8, width: 12, height: 12)).fill()
                }
                return true
            }
        }

        private static func captureSwitcherSnapshots(_ view: NSView) {
            guard ProcessInfo.processInfo.arguments.contains("--windows-taskbar-snapshots") else { return }
            let directory = URL(fileURLWithPath: "/tmp/docky-windows-snapshots", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch { preconditionFailure("Cannot create snapshots: \(error)") }
            for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                view.appearance = NSAppearance(named: appearance)
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    preconditionFailure("Switcher bitmap required")
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    preconditionFailure("Switcher PNG required")
                }
                do {
                    try png.write(to: directory.appendingPathComponent("switcher-\(name).png"))
                } catch { preconditionFailure("Cannot save snapshot: \(error)") }
            }
            view.appearance = nil
        }
    }
#endif
