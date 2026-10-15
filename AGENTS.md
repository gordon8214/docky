# AGENTS.md

This file provides guidance to coding agents (Claude Code, Codex) when working with code in this repository. `CLAUDE.md` is a symlink to it.

## Project

Docky is a Dock replacement for macOS 27+, Apple silicon only, drawn as a
Windows 11–style taskbar. This checkout is an AppKit fork (`origin` =
`gordon8214/docky`, `upstream` = `josejuanqm/docky`). All app-owned UI uses
AppKit and Core Animation. **The app does not use SwiftUI**, so
don't add `import SwiftUI` or hosting views. Swift 6 with
`SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` and approachable concurrency. The
only package dependency is Sparkle. Community widgets are disabled in this fork
(see `docs/external-widgets.md`). The app uses private SkyLight/CGS/AX SPI, so it
can't ship on the Mac App Store.

## Build

Run builds one at a time, because Xcode's shared build database locks. Each
configuration takes 3–5 minutes, so use a 10-minute timeout. The test scripts
expect this `-derivedDataPath`:

```bash
gtimeout 600 xcodebuild -project Docky.xcodeproj -scheme Docky -configuration Debug -destination 'platform=macOS' -derivedDataPath build/AppKitDerivedData CODE_SIGNING_ALLOWED=NO SWIFT_EMIT_LOC_STRINGS=NO build
```

- `SWIFT_EMIT_LOC_STRINGS=NO` stops verification builds from rewriting
  `Docky/Localizable.xcstrings`.
- An unsigned build carries the linker identifier `Docky`, not
  `gt.quintero.Docky`. The Dock-side bridge rejects that identifier and releases
  the screen reservation. Before launching the build or running live tests,
  ad-hoc sign it and keep the loader entitlement:

  ```bash
  codesign --force --deep --sign - --preserve-metadata=entitlements build/AppKitDerivedData/Build/Products/Debug/Docky.app
  ```

- `scripts/verify_architectures.sh <Docky.app>` checks each project-owned
  binary's architecture: the app and watchdog are `arm64`, both loaders and
  the Dock payload are `arm64e`, and the menu payload is `arm64 arm64e`.
  Update the script when you add or change a helper binary.
- Install locally with `.agents/skills/install-docky/scripts/install.sh`
  (the `install-docky` skill). It builds Release with real signing, replaces
  `/Applications/Docky.app`, and launches the new copy. Allow about 10 minutes
  for a first build. `--build-only` skips installation.
- `scripts/release_sparkle_update.sh` handles a Developer ID archive,
  notarization (when `NOTARYTOOL_PROFILE` is set), and the Sparkle appcast.
  Release builds bump `CFBundleVersion` to a `YYYYMMDDhhmm` timestamp and sync
  the watchdog's version.

Before finishing: run `git diff --check`, make sure there are no SwiftUI
imports, and use `otool -L` to confirm the app and its helpers don't link
SwiftUI.

## Tests

There is no XCTest target. Each script below is one bounded suite and the
smallest unit you can run. None of them filter individual tests. The scripts
use `gtimeout` and `gtail` from Homebrew coreutils. Failures are `precondition`
traps or nonzero exits.

**Standalone, no app build needed.** These scripts compile an explicit list of
app source files together with a harness in `scripts/tests/`. If an edited
source file gains a dependency on a type defined in another file, add that file
to the script's `swiftc` list.

| Script | Budget (compile/run) |
| --- | --- |
| `scripts/test_observation_bridge.sh` | 30s / 10s |
| `scripts/test_launchpad_scan.sh` (`-warnings-as-errors`) | 30s / 10s |
| `scripts/test_appkit_browser.sh` (geometry, drop insertion, Launchpad grid, preview capture sizing and refresh order, WindowServer tag and packet rules) | 45s / 15s |
| `scripts/test_appkit_compatibility.sh` (Settings history, legacy widget encoding) | 45s / 15s |
| `scripts/test_dock_payload.sh` (Dock payload and loader, Objective-C) | 30s / 10s |
| `scripts/test_native_menu_bridge.sh` (menu bridge protocol, loader stub bytes) | 30s / 5s |

**In-app, needs the Debug build above.** These scripts launch the built binary
with a `#if DEBUG` flag, which `AppDelegate.runDebugRegressionIfRequested`
routes to `Docky/Testing/`. Quit any running Docky before the dock-system,
bridge and lifecycle tests.

| Script | Notes |
| --- | --- |
| `scripts/test_appkit_ui.sh` | `--appkit-ui-regression`; under 15s, 30s cap. Covers every Settings pane, widgets, Windows taskbar, window switcher, menu extras toggle, file browser choice |
| `scripts/test_dock_system.sh` | `--dock-system-regression`; needs a WindowServer session |
| `scripts/test_dock_bridge.sh` | Signed build. Temporarily restarts Apple's Dock |
| `scripts/test_window_switcher.sh` | Unlocked desktop with existing Accessibility and Screen Recording grants; 45s cap. Holds real ⌃⌥⌘Tab key events for about two seconds, so don't type while it runs. Skips the ⌘Tab takeover check while another Docky runs |
| `scripts/test_window_registry.sh` | Same grants. Under 10s, longer when a window has no AX element; 30s cap plus any watch time. Checks the window list on every Space against WindowServer and CoreGraphics, thumbnails, and AX lookups. `--watch-registry <seconds>` prints live changes; `DOCKY_APP_BINARY` picks another build |
| `gtimeout 30 python3 scripts/test_dock_lifecycle.py` | Signed build. Kills Dock and the app to check reconnection and watchdog recovery, including handing ⌘Tab back to macOS |

Add `--windows-taskbar-snapshots` to `--appkit-ui-regression` to also write
light and dark renders to `/tmp/docky-windows-snapshots`. These suites don't
cover drag feel, auto-hide, VoiceOver, permission grants, or multi-display
behavior. Check those in a running build.

## Architecture

### Processes and injected helpers

- **Docky.app**: runs with the accessory activation policy. The dock is
  `MainWindow`, a nonactivating `NSPanel` at the real Dock window level.
- **DockyDockWatchdog**: a separate target embedded as a login item. If Docky
  exits unexpectedly, it restores Apple's Dock preferences from the snapshot
  that `SystemDockVisibilityService` writes to
  `~/Library/Application Support/Docky/`. In Debug builds it also serves
  `--visible-frame-probe`, which tests use for independent readback.
- **DockyDockBridge/** and **DockyMenuBridge/**: Objective-C loaders and
  payloads injected into Apple's Dock, MenuBarAgent, and menu-extra owner apps.
  The loaders are adapted from yabai. These aren't Xcode targets: the
  "Build Dock Integration Bridge" run-script phase calls `DockyDockBridge/build.sh`,
  which also runs `DockyMenuBridge/build.sh`. New sources there need build
  script changes. Injection needs task-port authorization; the development Mac
  has SIP disabled.
- `Docky/Private/` holds private SkyLight/CGS bindings, loaded dynamically.
  CONTRIBUTING asks that any change here document why the call is needed and
  what breaks without it.

### Screen reservation and the system Dock

- `SystemDockVisibilityService` hides Apple's Dock through its `com.apple.dock`
  preferences and snapshots the original values.
- `WindowReservationService` reconciles every 0.5s. It publishes geometry
  through `NativeDockIntegration` and the Dock-side payload, then verifies the
  result from a separate process. There is no Accessibility resize fallback.
- The verified ABI (macOS 27.0.1, 26A434) and the full design are in
  `docs/window-system-integration.md`. It also records the SkyLight window
  list, capture and notification SPI behind `WindowRegistry`, which lists
  windows on every Space. Native menu extras are in
  `docs/menu-extras-prototype.md`. Update these docs when you change the
  behavior or validation status they record.

### State

App state lives in `@MainActor` singletons (`.shared`) in `Docky/Services/`:

- `DockyPreferences`: `@Observable`; each property persists to `UserDefaults`
  in its `didSet`.
- `TileStore`: builds the tile row from the `com.apple.dock` plist
  (`persistent-apps`, `persistent-others`), running apps, and Docky's trailing
  items.
- `ProfileService`: mirrors the active profile into the top-level
  `DockyPreferences` keys.

Preference keys, profiles, and custom icon formats are compatibility contracts.
Existing user data must still decode. Keys that nothing reads anymore, such as
the old theme and classic-Dock appearance keys, stay in `UserDefaults` untouched.

### Observation

Services use two patterns: `ObservableObject` with `@Published` (Combine sinks)
and `@Observable`. Prefer `@Observable` for new code. `observeChanges { }` in
`ObservationBridge.swift` wraps `withObservationTracking` in an
`AnyCancellable`, so both patterns use the same `Set<AnyCancellable>` lifecycle.
Reusable controllers register their subscriptions with
`NativeObservationSession`, which stops them while hidden and restores them
when reopened.

### UI

- `AppDelegate` sets up services and routes `docky://` URLs (`handleDockyURL`).
- `MainWindowController` owns the overlay window controllers: Launchpad, window
  switcher, start menu, editor, and profile switcher.
- The taskbar is `DockRootView` → `DockCanvasView`, a flipped view with
  explicit frames. `DockCanvasController` drives it and holds layout and drag
  state separately from the views. `WindowsTaskbarCanvas` lays out the Start
  button and app buttons; most other tiles (folders, stacks, widgets) live in
  the tray's overflow popup, and folders dropped on the tray join them. Trash
  has its own tray button, which takes drops like the Trash tile.
  The taskbar lays out horizontally only, so `effectiveWindowPosition` keeps it
  at the bottom for now.
- `WindowsTaskbarStyle` (a stateless enum) is Docky's only appearance. The
  taskbar's colors, fonts, motion, and `WindowsTaskbarMetrics` live in code, and
  `WindowsTaskbarStyle.Tray` styles tiles off the taskbar (the tray's overflow
  popup and drag previews). There are no themes; build new appearances on this
  type.
- Tile behavior lives in the `DockTileInteraction` struct. Pure geometry is in
  `Dock*Geometry.swift` and `WindowSwitcherGeometry.swift`, which is why the
  standalone test scripts can compile it on its own.
- The window switcher (`WindowSwitcherService` + `WindowSwitcherController`)
  looks and behaves like Windows 11 Alt+Tab. "Replace macOS ⌘Tab" turns off the
  system ⌘Tab through `SystemCommandTabService`. See `docs/appkit-port.md`.
- Large types are split into `Type+Concern.swift` extensions.

## Conventions

- The project uses file-system-synchronized groups. New files under `Docky/`
  or `DockyDockWatchdog/` join their target without edits to `project.pbxproj`.
- At startup the app caps every AX call at 1s with
  `AXUIElementSetMessagingTimeout`. Keep new AX work bounded too.
- Log through `Logger(subsystem: "gt.quintero.Docky", category: …)`.
- Give layer-backed views shadows through `NSView.shadow`, not the backing
  layer's `shadow…` properties. AppKit resets the layer's `shadowOpacity` when
  the view moves into a window, and clips a view whose layer has a corner
  radius unless it has an `NSView.shadow`. On a flipped view, a positive
  offset falls downward.
- To preview features gated by older OS versions in Debug, run
  `defaults write gt.quintero.Docky DebugPreferredOSVersion <version>` (see
  `FeatureGate`).
- Commit subjects on this fork are plain imperative sentences ("Fix runaway
  window switcher previews"). The `type(scope):` style in the PR template comes
  from upstream.
