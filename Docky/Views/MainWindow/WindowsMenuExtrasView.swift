import AppKit
import Combine

/// Captured native menu-extra appearances, with their original owner handling activation.
final class WindowsMenuExtrasView: NSView {
    private let scroll = NSScrollView()
    private let content = NSView()
    private let placeholder = NSButton()
    private var buttons: [String: NSButton] = [:]
    private let owner = UUID()
    private var observation: AnyCancellable?
    private var permissions: PermissionsWindowController?
    override var isFlipped: Bool { true }
    var preferredWidth: CGFloat { max(32, min(448, CGFloat(buttons.count) * 32)) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .none
        scroll.documentView = content
        addSubview(scroll)
        placeholder.isBordered = false
        placeholder.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Menu extras")
        placeholder.target = self
        placeholder.action = #selector(showPermissions)
        addSubview(placeholder)
    }
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observation?.cancel()
        observation = nil
        if window == nil {
            MenuExtrasService.shared.detach(owner)
            return
        }
        MenuExtrasService.shared.attach(owner)
        observation = observeChanges { [weak self] in
            _ = MenuExtrasService.shared.items
            _ = MenuExtrasService.shared.message
            _ = MenuExtrasService.shared.lastActivation
            self?.refresh()
        }
    }

    func refresh() {
        let extras = displayedItems
        let kept = Set(extras.map(\.id))
        for identifier in Array(buttons.keys) where !kept.contains(identifier) {
            buttons.removeValue(forKey: identifier)?.removeFromSuperview()
        }
        for extra in extras {
            let button = buttons[extra.id] ?? NSButton()
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.image = MenuExtraImage.adaptingMonochrome(
                extra.image, to: WindowsTaskbarStyle.foreground(effectiveAppearance))
            button.contentTintColor = WindowsTaskbarStyle.foreground(effectiveAppearance)
            button.identifier = NSUserInterfaceItemIdentifier(extra.id)
            button.setAccessibilityLabel(extra.snapshot.label)
            button.toolTip = extra.snapshot.label
            button.target = self
            button.action = #selector(openExtra(_:))
            button.menu = actionMenu(for: extra.id)
            if button.superview == nil { content.addSubview(button) }
            buttons[extra.id] = button
        }
        toolTip = MenuExtrasService.shared.message
        placeholder.isHidden = !extras.isEmpty
        placeholder.toolTip = MenuExtrasService.shared.message
        placeholder.setAccessibilityLabel(MenuExtrasService.shared.message)
        placeholder.isEnabled = !AXIsProcessTrusted() || !CGPreflightScreenCaptureAccess()
        needsLayout = true
        superview?.needsLayout = true
    }

    private func actionMenu(for identifier: String) -> NSMenu {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Original Menu", action: #selector(openExtra(_:)), keyEquivalent: "")
        open.target = self
        open.representedObject = identifier
        menu.addItem(open)
        let experiment = NSMenuItem(title: "Try Native Popup Above Dock", action: #selector(tryPopup(_:)),
                                    keyEquivalent: "")
        experiment.target = self
        experiment.representedObject = identifier
        menu.addItem(experiment)
        if !MenuExtrasService.shared.lastActivation.isEmpty {
            menu.addItem(.separator())
            let result = NSMenuItem(title: MenuExtrasService.shared.lastActivation, action: nil, keyEquivalent: "")
            result.isEnabled = false
            menu.addItem(result)
        }
        return menu
    }

    private var displayedItems: [MenuExtra] {
        guard let number = window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return [] }
        return MenuExtrasService.shared.items.filter {
            $0.snapshot.displayID == number.uint32Value
                && $0.snapshot.ownerPID != ProcessInfo.processInfo.processIdentifier
                && !$0.id.contains("com.apple.menuextra.clock")
        }
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        placeholder.frame = bounds
        let extras = displayedItems
        content.frame = CGRect(x: 0, y: 0, width: CGFloat(extras.count) * 32, height: 40)
        for (index, extra) in extras.enumerated() {
            buttons[extra.id]?.frame = CGRect(x: CGFloat(index) * 32, y: 4, width: 32, height: 32)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    @objc private func openExtra(_ sender: Any) { activate(sender, relocate: false) }
    @objc private func tryPopup(_ sender: Any) { activate(sender, relocate: true) }
    private func activate(_ sender: Any, relocate: Bool) {
        let identifier = (sender as? NSMenuItem)?.representedObject as? String
            ?? (sender as? NSButton)?.identifier?.rawValue
        guard let identifier, let extra = displayedItems.first(where: { $0.id == identifier }),
              let button = buttons[identifier], let window, let screen = window.screen else { return }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let reference = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let anchor = CGRect(x: rect.minX, y: reference - rect.maxY, width: rect.width, height: rect.height)
        let visible = CGRect(x: screen.visibleFrame.minX, y: reference - screen.visibleFrame.maxY,
                             width: screen.visibleFrame.width, height: screen.visibleFrame.height)
        MenuExtrasService.shared.activate(extra.snapshot, anchor: anchor, visible: visible, relocate: relocate)
    }

    @objc private func showPermissions() {
        let steps: [Permission] = [.accessibility, .screenCapture].filter {
            PermissionsService.shared.status(for: $0) != .granted
        }
        permissions = PermissionsWindowController(steps: steps)
        permissions?.showWindow(nil)
    }
}
