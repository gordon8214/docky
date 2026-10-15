//
//  ContextActionPopover.swift
//  Docky
//

import AppKit
import ObjectiveC

struct ContextAction: Identifiable {
    enum Kind: Equatable {
        case action
        case submenu
        case lazySubmenu
        case customView
        case share(URL)
        case divider
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let image: NSImage?
    let customView: NSView?
    let isDestructive: Bool
    let isOn: Bool
    let children: [ContextAction]
    let childrenProvider: (() -> [ContextAction])?
    let handler: () -> Void

    static func action(
        _ title: String,
        image: NSImage? = nil,
        isDestructive: Bool = false,
        isOn: Bool = false,
        handler: @escaping () -> Void
    ) -> Self {
        Self(
            kind: .action,
            title: title,
            image: image,
            customView: nil,
            isDestructive: isDestructive,
            isOn: isOn,
            children: [],
            childrenProvider: nil,
            handler: handler
        )
    }

    static func submenu(_ title: String, children: [ContextAction]) -> Self {
        Self(
            kind: .submenu,
            title: title,
            image: nil,
            customView: nil,
            isDestructive: false,
            isOn: false,
            children: children,
            childrenProvider: nil,
            handler: {}
        )
    }

    static func lazySubmenu(
        _ title: String,
        image: NSImage? = nil,
        childrenProvider: @escaping () -> [ContextAction]
    ) -> Self {
        Self(
            kind: .lazySubmenu,
            title: title,
            image: image,
            customView: nil,
            isDestructive: false,
            isOn: false,
            children: [],
            childrenProvider: childrenProvider,
            handler: {}
        )
    }

    static func customView(_ view: NSView) -> Self {
        Self(
            kind: .customView,
            title: "",
            image: nil,
            customView: view,
            isDestructive: false,
            isOn: false,
            children: [],
            childrenProvider: nil,
            handler: {}
        )
    }

    static func share(_ url: URL) -> Self {
        Self(
            kind: .share(url),
            title: String(localized: "Share"),
            image: nil,
            customView: nil,
            isDestructive: false,
            isOn: false,
            children: [],
            childrenProvider: nil,
            handler: {}
        )
    }

    static var divider: Self {
        Self(
            kind: .divider,
            title: "",
            image: nil,
            customView: nil,
            isDestructive: false,
            isOn: false,
            children: [],
            childrenProvider: nil,
            handler: {}
        )
    }
}

enum ContextActionMenuPresenter {
    #if DEBUG
    /// Regression-harness seam: receives the built native menu and its anchor rectangle in
    /// place of modal tracking, while the presentation and autohide hold are active.
    @MainActor static var testInterceptor: ((NSMenu, NSRect, NSView) -> Void)?
    #endif
    @MainActor
    final class Coordinator: NSObject {
        private weak var interactionWindow: (any DockWindowInteractionHolding)?
        private let preferredEdge: NSRectEdge
        private let onPresentationChanged: (Bool) -> Void
        private var isInterruptingAutohide = false
        private var interactionToken: UUID?

        init(preferredEdge: NSRectEdge, onPresentationChanged: @escaping (Bool) -> Void) {
            self.preferredEdge = preferredEdge
            self.onPresentationChanged = onPresentationChanged
            super.init()
        }

        private func popUpCartouche(menu: NSMenu, in view: NSView, anchorRect: NSRect?) {
            onPresentationChanged(true)
            defer { onPresentationChanged(false) }
            beginAutohideInterruption(for: view)
            defer { endAutohideInterruption() }

            let anchorRect = anchorRect ?? view.bounds
            #if DEBUG
            if let interceptor = ContextActionMenuPresenter.testInterceptor {
                interceptor(menu, anchorRect, view)
                return
            }
            #endif
            let selector = NSSelectorFromString("_popUpMenuRelativeToRect:inView:preferredEdge:")
            if menu.responds(to: selector) {
                typealias Fn = @convention(c) (NSMenu, Selector, NSRect, NSView?, NSRectEdge) -> Void
                let imp = menu.method(for: selector)
                let fn = unsafeBitCast(imp, to: Fn.self)
                fn(menu, selector, anchorRect, view, preferredEdge)
                return
            }

            menu.update()
            let anchor: NSPoint
            switch preferredEdge {
            case .minX:
                anchor = NSPoint(x: anchorRect.minX, y: anchorRect.midY)
            case .maxX:
                anchor = NSPoint(x: anchorRect.maxX, y: anchorRect.midY)
            case .minY:
                anchor = NSPoint(x: anchorRect.midX - menu.size.width / 2, y: anchorRect.minY)
            case .maxY:
                anchor = NSPoint(x: anchorRect.midX - menu.size.width / 2, y: anchorRect.maxY)
            @unknown default:
                anchor = NSPoint(x: anchorRect.midX - menu.size.width / 2, y: anchorRect.maxY)
            }
            menu.popUp(positioning: menu.items.last, at: anchor, in: view)
        }

        private func beginAutohideInterruption(for view: NSView) {
            guard !isInterruptingAutohide else { return }
            // End the hold on the window that issued the token: the anchor can
            // leave its window while the menu tracks.
            interactionWindow = view.window as? any DockWindowInteractionHolding
            interactionToken = interactionWindow?.beginInteraction()
            isInterruptingAutohide = true
        }

        private func endAutohideInterruption() {
            guard isInterruptingAutohide else { return }
            interactionWindow?.endInteraction(interactionToken)
            interactionWindow = nil
            interactionToken = nil
            isInterruptingAutohide = false
        }

        private func buildMenu(actions: [ContextAction]) -> NSMenu {
            let menu = NSMenu()
            for action in actions {
                addMenuItem(for: action, to: menu)
            }
            return menu
        }

        private func addMenuItem(for action: ContextAction, to menu: NSMenu) {
            switch action.kind {
            case .action:
                let item = NSMenuItem(title: action.title, action: #selector(runAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = action
                item.state = action.isOn ? .on : .off
                item.image = thumbnailImage(action.image)
                if action.isDestructive {
                    item.attributedTitle = NSAttributedString(
                        string: action.title,
                        attributes: [.foregroundColor: NSColor.systemRed]
                    )
                }
                menu.addItem(item)
            case .submenu:
                let item = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
                item.image = thumbnailImage(action.image)
                item.submenu = buildMenu(actions: action.children)
                menu.addItem(item)
            case .lazySubmenu:
                let item = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
                item.image = thumbnailImage(action.image)
                let submenu = NSMenu(title: action.title)
                let provider = action.childrenProvider ?? { [] }
                let controller = LazyMenuController(provider: provider) { [weak self] menu, children in
                    guard let self else { return }
                    menu.removeAllItems()
                    for child in children {
                        self.addMenuItem(for: child, to: menu)
                    }
                }
                submenu.delegate = controller
                objc_setAssociatedObject(submenu, &lazyMenuControllerKey, controller, .OBJC_ASSOCIATION_RETAIN)
                item.submenu = submenu
                menu.addItem(item)
            case .customView:
                let item = NSMenuItem()
                item.view = action.customView
                menu.addItem(item)
            case .share(let url):
                let picker = NSSharingServicePicker(items: [url])
                let item = picker.standardShareMenuItem
                // Keep the picker alive for the menu item's action target.
                objc_setAssociatedObject(item, &sharingPickerKey, picker, .OBJC_ASSOCIATION_RETAIN)
                menu.addItem(item)
            case .divider:
                menu.addItem(.separator())
            }
        }

        private func thumbnailImage(_ image: NSImage?) -> NSImage? {
            guard let image else { return nil }
            guard let copy = image.copy() as? NSImage else { return image }
            copy.size = NSSize(width: 16, height: 16)
            return copy
        }

        @objc private func runAction(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? ContextAction else { return }
            action.handler()
        }
    }
}

@MainActor private var lazyMenuControllerKey: UInt8 = 0
@MainActor private var sharingPickerKey: UInt8 = 0

@MainActor
private final class LazyMenuController: NSObject, NSMenuDelegate {
    private let provider: () -> [ContextAction]
    private let populate: (NSMenu, [ContextAction]) -> Void

    init(
        provider: @escaping () -> [ContextAction],
        populate: @escaping (NSMenu, [ContextAction]) -> Void
    ) {
        self.provider = provider
        self.populate = populate
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu, provider())
    }
}

extension ContextActionMenuPresenter {
    /// Shows `actions` as a native Dock-style menu anchored to `anchorView`.
    /// The menu build, autohide interruption, and private
    /// `_popUpMenuRelativeToRect:` call are delegated to a transient
    /// Coordinator. `anchorRect`, in `anchorView` coordinates, narrows the
    /// anchor to part of the view, such as the pointer location on a wide bar.
    @MainActor static func popUpMenu(
        actions: [ContextAction],
        from anchorView: NSView,
        anchorRect: NSRect? = nil,
        preferredEdge: NSRectEdge = .maxY,
        onPresentationChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        guard !actions.isEmpty else { return }
        // A visible or pending Windows tooltip would otherwise linger beside the menu while it tracks.
        WindowsTaskbarTooltip.shared.dismiss()
        let coordinator = Coordinator(preferredEdge: preferredEdge, onPresentationChanged: onPresentationChanged)
        coordinator.presentMenu(actions: actions, from: anchorView, anchorRect: anchorRect)
    }
}

extension ContextActionMenuPresenter.Coordinator {
    /// Builds and tracks the menu for `ContextActionMenuPresenter.popUpMenu`.
    fileprivate func presentMenu(actions: [ContextAction], from anchorView: NSView, anchorRect: NSRect?) {
        popUpCartouche(menu: buildMenu(actions: actions), in: anchorView, anchorRect: anchorRect)
    }
}
