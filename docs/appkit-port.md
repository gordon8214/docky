# AppKit UI

This fork targets macOS 27 and renders app-owned UI with AppKit and Core Animation.
The Dock uses a flipped canvas, stable tile views, explicit frames, and native scroll
views for overflowing sections. Native collection and table views power launchers,
folder browsers, previews, and the editor. Settings uses a split-view sidebar and
native controls. The existing custom glass backdrop remains a direct AppKit view.

Models, preference keys, profiles, theme manifests, custom icons, window-management
services, private APIs, Sparkle, and the Dock watchdog retain their existing formats
and entry points. Supported `docky:` actions remain available. Community widget
installation is disabled; see [legacy compatibility](external-widgets.md).

## Building

Builds are sequential to avoid Xcode's shared build-database lock. Budget 3–5 minutes
per configuration, with a 10-minute timeout. Use the `Docky` scheme. For an unsigned
Apple silicon verification build:

```sh
gtimeout 600 xcodebuild -project Docky.xcodeproj -scheme Docky \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/AppKitDerivedData \
  CODE_SIGNING_ALLOWED=NO SWIFT_EMIT_LOC_STRINGS=NO build
```

Repeat with `-configuration Release` after Debug completes. Localization extraction
is disabled for verification so builds do not rewrite the string catalog. The project
defaults to `arm64` for Docky and its watchdog; the Dock bridge builds as `arm64e`.
Vendor frameworks retain their supplied architectures and signatures.

These verification builds disable code signing. Before launching either build,
ad-hoc sign the app and verify its signature using the commands in
[Window system integration](window-system-integration.md#regression-commands).
The reservation helper rejects Xcode's temporary linker signature, leaving
windows free to extend under Docky.

Verify each built app with:

```sh
scripts/verify_architectures.sh build/AppKitDerivedData/Build/Products/Debug/Docky.app
```

The release script runs this check on the exported app before notarization and
packaging. It checks project-owned binaries and excludes vendor frameworks.

## Regressions

- `scripts/test_observation_bridge.sh`: compilation 30 seconds, runtime 10 seconds.
- `scripts/test_launchpad_scan.sh`: compilation 30 seconds, runtime 10 seconds.
- `scripts/test_appkit_browser.sh`: compilation 45 seconds, runtime 15 seconds.
  Covers all Dock edges, screen coordinates, scroll-adjusted drop insertion,
  target rejection, Launchpad page geometry, window switcher rows and ↑/↓
  navigation, search keys, and controller release.
- `scripts/test_appkit_compatibility.sh`: compilation 45 seconds, runtime 15 seconds.
  Covers Settings history and legacy widget kind, span, and opaque-settings encoding.
- `scripts/test_appkit_ui.sh`: a previously built Debug app, runtime 30 seconds;
  normally under 15 seconds. Exercises every Settings pane twice, built-in and
  legacy widget spans, compact/expanded layout, canceled drag mouse-up, and observer
  release. Also covers isolated Launchpad folder mutations and drop indexes,
  grid keyboard navigation, dismissed folder callbacks, file context menus,
  calendar dates, denied-permission controls, initial lyric scrolling, widget reuse,
  badge limits, cached Hidden Apps updates, and the window switcher's cards,
  selection frame, hover close button, and icon fallback, built from fixture windows.
  The test entry point bypasses normal startup and exits without installing
  the app or requesting permissions.
- `scripts/test_window_switcher.sh`: a signed Debug app, normally under 15 seconds,
  runtime budget 45 seconds. Requires an unlocked desktop with existing Accessibility
  and screen capture permissions. Checks the reveal delay, selection feedback in
  both preview modes, a real in-place preview, rapid selection changes, dismissal,
  key swallowing, the quick-tap switch, and the ⌘Tab takeover. The ⌘Tab check is
  skipped while another Docky is running. Temporarily changed switcher
  preferences and the frontmost app are restored.

The integration checks validate native controller layout and lifecycle. They do not
replace interactive checks for drag sessions, magnification, auto-hide, VoiceOver,
permission grants, window-management actions, or physical display configurations.
Verify those in a running build, along with themes, light/dark appearance, reduced
motion, and reduced transparency.

Before finalizing, run `git diff --check`, search app sources for SwiftUI imports and
hosting adapters, and inspect the main app and its app-owned helper binaries with
`otool -L` for SwiftUI linkage.

## Window switcher

The window switcher looks and behaves like the Windows 11 Alt+Tab switcher in
every theme. `WindowSwitcherController` centers an acrylic panel
(`WindowsTaskbarPopupChrome`) of window cards on the dock's screen.
`WindowSwitcherGeometry` gives every thumbnail one height (15% of the screen,
96–160 points), takes each card's width from its window's aspect ratio, and wraps
cards into centered rows at 85% of the screen width. Each card shows the app
icon and window title above the thumbnail, a 3-point selection frame, and a
close button on hover. Windows without a capture show their app icon.

Pressing and releasing the shortcut within 120 ms switches to the previous window
without showing the switcher. After that delay it appears at once and fades out
on dismissal. While it is open, Tab and the arrow keys move the
selection (↑ and ↓ follow the rows on screen), Delete closes the selected window,
Return or releasing the modifier switches, Escape or a click outside the panel
cancels, and every other key is swallowed so ⌘Q and ⌘H can't reach Docky.

"Replace macOS ⌘Tab" in Window Management makes ⌘Tab the shortcut.
`SystemCommandTabService` turns off WindowServer's ⌘Tab (1) and ⇧⌘Tab (2)
symbolic hotkeys with `CGSSetSymbolicHotKeyEnabled`. The Dock matches those
ahead of every Carbon hotkey, so Docky's own ⌘Tab hotkey can't fire while they
are on. Docky only turns them off while its ⌘Tab hotkey is registered and
Accessibility is granted. The setting outlives the process, so Docky turns them
back on when it quits, from an exit handler, and on its next launch after a
crash. The watchdog also turns them back on after a forced termination, because
the visibility state file records the override. Debug regressions never take
⌘Tab unless a check needs it and no other Docky is running.
`scripts/test_dock_lifecycle.py` checks the watchdog path.

## Windows 11 taskbar

The right-side tray includes a prototype for actual macOS menu extras. See
[menu-extra behavior, validation, and native popup findings](menu-extras-prototype.md).

The bundled `windows` theme uses the optional `behavior.taskbarStyle: "windows11"`
preset. It resolves a bottom, full-width bar without rewriting saved placement,
size, magnification, appearance overrides, or tile order. The bar is 48 points
tall by default, with 40-point buttons, 24-point icons, and 44-point pitch.
Dragging its top edge, or the Taskbar Size field in Settings, sets the height
from 32 to 96 points (`windowsTaskbarHeight`), and `WindowsTaskbarMetrics`
scales every button, icon, indicator, badge, and tray control with it. Native
menu extras keep their menu-bar size, so their slots grow but never shrink. Additional tiles remain
available through the tray overflow; battery details are available in the battery
context menu. Status controls reflect Mac state and open Mac settings.

App insertion and removal use keyframes sampled from `Windows Taskbar Behavior.mov`
at source timestamps 11.742–12.033 and 14.175–14.408 seconds. The recording has
variable timestamps (1,090 source frames), so nominal 120-fps frame counts are not
used for timing. Icon entrance samples at 11.933–12.433 seconds reproduce the
delayed rise and damped bounce independently of recentering. Windows presentation
uses AppKit and Core Animation throughout.

The AppKit UI regression entry point includes taskbar geometry, theme round-tripping,
preserved preferences, cancellation, and popup cleanup. To also write dark/light
rendering snapshots to `/tmp/docky-windows-snapshots`, add
`--windows-taskbar-snapshots` alongside `--appkit-ui-regression` when running a
previously built Debug app (30-second runtime budget). These snapshots do not
replace a desktop material, live motion, VoiceOver, or Windows VM comparison.
Segoe UI is used when installed; otherwise text uses the system font, whose glyph
shapes differ from Windows.
