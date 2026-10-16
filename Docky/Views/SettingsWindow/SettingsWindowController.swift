//
//  SettingsWindowController.swift
//  Docky
//

import AppKit

/// The Settings window. Its sidebar runs up beside the traffic lights under a
/// unified toolbar, and the window is titled after the selected pane.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let frameAutosaveName = "DockySettingsWindow"
    var onClose: (() -> Void)?
    let settings: NativeSettingsController
    private let autosavesFrame: Bool

    /// Tests pass their own defaults and turn off frame autosave, so they don't
    /// change the user's saved window frame or last pane.
    init(defaults: UserDefaults = .standard, autosavesFrame: Bool = true) {
        settings = NativeSettingsController(defaults: defaults)
        self.autosavesFrame = autosavesFrame
        // The window's title follows the content view controller's title.
        let window = NSWindow(contentViewController: settings)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.titleVisibility = .visible
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenNone)
        window.setContentSize(NSSize(width: 820, height: 600))
        window.contentMinSize = NSSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let toolbar = NSToolbar(identifier: "DockySettingsToolbar")
        toolbar.delegate = self
        // The default display mode reserves a row for item labels, which makes the bar too tall.
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar
        settings.onNavigationChange = { [weak window] in window?.toolbar?.validateVisibleItems() }
        if !autosavesFrame || !window.setFrameAutosaveName(Self.frameAutosaveName)
            || !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
    }

    required init?(coder: NSCoder) { nil }

    func showPane(_ pane: SettingsPane) { settings.showPane(pane) }

    func windowWillClose(_ notification: Notification) {
        // End any edit in progress, so a number typed without pressing Return
        // still saves.
        window?.makeFirstResponder(nil)
        if autosavesFrame {
            window?.saveFrame(usingName: Self.frameAutosaveName)
            // AppDelegate makes a new window controller each time Settings opens.
            // Release the name, so the next window can autosave under it.
            window?.setFrameAutosaveName("")
        }
        onClose?()
    }
}
