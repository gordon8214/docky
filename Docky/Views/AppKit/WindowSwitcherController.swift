//
//  WindowSwitcherController.swift
//  Docky
//
//  The Windows 11–style window switcher: a centered acrylic panel of window
//  cards that wrap into rows. Fills the screen-sized overlay window so the
//  in-place preview can sit at the selected window's real position behind
//  the panel, and so a click outside the panel cancels.
//

import AppKit
import Combine

final class WindowSwitcherController: NSViewController {
    static let emptyPanelSize = CGSize(width: 320, height: 96)
    static let tintAlpha: CGFloat = 0.82

    private let focusedImage = WindowSwitcherPassthroughImageView()
    let panelView = NSView()
    private let chrome = WindowsTaskbarPopupChrome(frame: .zero)
    private let scrollView = NSScrollView()
    private let documentView = WindowSwitcherDocumentView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let observations = NativeObservationSession()
    private var refreshIsScheduled = false

    private(set) var cardViews: [String: WindowSwitcherCardView] = [:]
    private(set) var orderedIDs: [String] = []
    private(set) var geometry: WindowSwitcherGeometry?
    private var selectedID: String?

    override func loadView() {
        let root = WindowSwitcherRootView()
        root.onClickOutsidePanel = { WindowSwitcherService.shared.dismiss() }
        root.panelView = panelView

        focusedImage.imageScaling = .scaleProportionallyUpOrDown
        focusedImage.isHidden = true
        root.addSubview(focusedImage)

        // AppKit owns a layer-backed view's shadow and resets the layer's
        // shadow opacity, so the shadow goes through `NSView.shadow`.
        panelView.wantsLayer = true
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 16
        shadow.shadowOffset = CGSize(width: 0, height: -4)
        panelView.shadow = shadow
        root.addSubview(panelView)

        chrome.tintAlpha = Self.tintAlpha
        chrome.borderWidth = 1
        chrome.borderAlpha = 0.25
        panelView.addSubview(chrome)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = documentView
        // The chrome's tint layer sits at zPosition 1; content must render above it.
        scrollView.wantsLayer = true
        scrollView.layer?.zPosition = 2
        chrome.addSubview(scrollView)

        emptyLabel.stringValue = String(localized: "No windows available")
        emptyLabel.font = WindowsTaskbarStyle.font(size: 14)
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.wantsLayer = true
        emptyLabel.layer?.zPosition = 2
        chrome.addSubview(emptyLabel)

        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let service = WindowSwitcherService.shared
        service.verticalNeighbor = { [weak self] identifier, direction in
            self?.verticalNeighbor(of: identifier, direction: direction)
        }
        observations.add { [weak self] in
            service.$windows.combineLatest(service.$selectedWindowIdentifier, service.$windowPreviews)
                .sink { [weak self] _ in self?.scheduleRefresh() }
        }
        observations.add { [weak self] in
            service.$focusedPreview.receive(on: DispatchQueue.main).sink { [weak self] preview in
                self?.updateFocusedPreview(preview)
            }
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        observations.start()
        refresh()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateFocusedPreview(WindowSwitcherService.shared.focusedPreview)
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        observations.stop()
        focusedImage.image = nil
        focusedImage.isHidden = true
        // Tracking areas don't report an exit when the window orders out.
        cardViews.values.forEach { $0.setHovered(false) }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutPanel()
        layoutFocusedPreview()
    }

    // MARK: Content

    /// Shows the given cards. `refresh()` feeds this from the switcher
    /// service; the UI regression calls it directly with fixtures.
    func display(cards: [WindowSwitcherCard], selectedID: String?) {
        let ids = cards.map(\.id)
        for (id, cardView) in cardViews where !ids.contains(id) {
            cardView.removeFromSuperview()
            cardViews[id] = nil
        }
        for card in cards {
            if let cardView = cardViews[card.id] {
                cardView.update(card)
            } else {
                let cardView = makeCardView(for: card)
                cardViews[card.id] = cardView
                documentView.addSubview(cardView)
            }
        }
        orderedIDs = ids
        self.selectedID = selectedID
        for (id, cardView) in cardViews {
            cardView.isSelected = id == selectedID
        }

        updateGeometry(screenSize: view.bounds.size)
        emptyLabel.isHidden = !cards.isEmpty
        scrollView.isHidden = cards.isEmpty
        layoutPanel()
        scrollSelectionToVisible()
    }

    private func makeCardView(for card: WindowSwitcherCard) -> WindowSwitcherCardView {
        let cardView = WindowSwitcherCardView(card: card)
        let id = card.id
        cardView.onConfirm = {
            let service = WindowSwitcherService.shared
            service.selectWindow(withIdentifier: id)
            service.confirmSelection()
        }
        cardView.onClose = {
            WindowSwitcherService.shared.closeWindow(withIdentifier: id)
        }
        cardView.onContextMenu = { [weak self] cardView in
            self?.showContextMenu(forWindowWithIdentifier: id, from: cardView)
        }
        return cardView
    }

    private func scheduleRefresh() {
        guard !refreshIsScheduled else { return }
        refreshIsScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshIsScheduled = false
            self.refresh()
        }
    }

    func refresh() {
        let service = WindowSwitcherService.shared
        let cards = service.windows.map { window in
            let thumbnail = service.windowPreview(for: window)
            return WindowSwitcherCard(
                id: window.windowIdentifier,
                title: window.windowTitle,
                appName: window.appDisplayName,
                icon: IconCacheService.shared.icon(forBundleIdentifier: window.bundleIdentifier),
                thumbnail: thumbnail,
                aspectRatio: Self.aspectRatio(thumbnail: thumbnail, frame: window.screenBounds)
            )
        }
        display(cards: cards, selectedID: service.selectedWindowIdentifier)
    }

    static func aspectRatio(thumbnail: NSImage?, frame: CGRect?) -> CGFloat {
        if let size = thumbnail?.size, size.width > 0, size.height > 0 {
            return size.width / size.height
        }
        if let frame, frame.width > 0, frame.height > 0 {
            return frame.width / frame.height
        }
        return WindowSwitcherGeometry.Metrics.defaultAspectRatio
    }

    // MARK: Layout

    private func layoutPanel() {
        let bounds = view.bounds
        guard !bounds.isEmpty else { return }

        if geometryScreenSize != bounds.size {
            updateGeometry(screenSize: bounds.size)
        }
        let panelSize = orderedIDs.isEmpty ? Self.emptyPanelSize : (geometry?.panelSize ?? Self.emptyPanelSize)

        let panelFrame = CGRect(
            x: round((bounds.width - panelSize.width) / 2),
            y: round((bounds.height - panelSize.height) / 2),
            width: panelSize.width, height: panelSize.height)
        panelView.frame = panelFrame
        panelView.layer?.shadowPath = CGPath(
            roundedRect: panelView.bounds, cornerWidth: 8, cornerHeight: 8, transform: nil)
        chrome.frame = panelView.bounds
        scrollView.frame = chrome.bounds

        let labelHeight = ceil(emptyLabel.intrinsicContentSize.height)
        emptyLabel.frame = CGRect(
            x: 12, y: (chrome.bounds.height - labelHeight) / 2,
            width: chrome.bounds.width - 24, height: labelHeight)
        emptyLabel.textColor = WindowsTaskbarStyle.foreground(view.effectiveAppearance).withAlphaComponent(0.7)

        guard let geometry else { return }
        documentView.frame = CGRect(origin: .zero, size: geometry.contentSize)
        for (index, id) in orderedIDs.enumerated() where geometry.cardFrames.indices.contains(index) {
            cardViews[id]?.frame = geometry.cardFrames[index]
        }
    }

    private var geometryScreenSize: CGSize?

    private func updateGeometry(screenSize: CGSize) {
        geometryScreenSize = screenSize
        geometry = WindowSwitcherGeometry(
            aspectRatios: orderedIDs.compactMap { cardViews[$0]?.card.aspectRatio },
            screenSize: screenSize)
    }

    private func scrollSelectionToVisible() {
        guard let selectedID, let cardView = cardViews[selectedID] else { return }
        let padding = WindowSwitcherGeometry.Metrics.panelPadding
        cardView.scrollToVisible(cardView.bounds.insetBy(dx: -padding, dy: -padding))
    }

    private func verticalNeighbor(of identifier: String, direction: Int) -> String? {
        guard let geometry,
              let index = orderedIDs.firstIndex(of: identifier),
              let neighbor = geometry.neighbor(of: index, direction: direction) else {
            return nil
        }
        return orderedIDs[neighbor]
    }

    // MARK: In-place preview

    private func updateFocusedPreview(_ preview: FocusedWindowPreview?) {
        focusedImage.image = preview?.image
        focusedImage.isHidden = preview == nil
        layoutFocusedPreview()
    }

    private func layoutFocusedPreview() {
        guard let preview = WindowSwitcherService.shared.focusedPreview, let window = view.window else {
            return
        }
        let windowRect = window.convertFromScreen(preview.screenBounds)
        focusedImage.frame = view.convert(windowRect, from: nil)
    }

    // MARK: Context menu

    private func showContextMenu(forWindowWithIdentifier identifier: String, from cardView: NSView) {
        let service = WindowSwitcherService.shared
        guard let window = service.windows.first(where: { $0.windowIdentifier == identifier }) else { return }
        let actions = windowCardContextActions(
            for: window,
            onClosed: { service.removeWindow(withIdentifier: identifier) },
            dismiss: { service.dismiss() }
        )
        ContextActionMenuPresenter.popUpMenu(actions: actions, from: cardView) { presented in
            service.setContextMenuPresented(presented)
        }
    }
}

/// Screen-sized root. A press that lands outside the panel cancels the switcher.
final class WindowSwitcherRootView: NSView {
    var onClickOutsidePanel: (() -> Void)?
    weak var panelView: NSView?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let panelView, panelView.frame.contains(point) { return }
        onClickOutsidePanel?()
    }
}

final class WindowSwitcherDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// The in-place preview never takes clicks, so presses fall through to the root.
final class WindowSwitcherPassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
