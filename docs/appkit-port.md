# AppKit UI

This fork targets macOS 27 and renders app-owned UI with AppKit and Core Animation.
Its only appearance is a Windows 11–style taskbar (see below), drawn on a flipped
canvas with stable tile views, explicit frames, and a native scroll view for
overflowing app buttons. Native collection and table views power launchers,
folder browsers, previews, and the editor. Settings uses a split-view sidebar and
native controls.

Models, preference keys, profiles, custom icons, window-management services,
private APIs, Sparkle, and the Dock watchdog retain their existing formats and
entry points. The theme system and the classic macOS-Dock look are gone; their
preference keys stay in `UserDefaults` unread, and `.dockytheme` files no longer
open in Docky. Supported `docky:` actions remain available. Community widget
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
  selection frame, hover close button, icon fallback, and header font and icon
  sizes, built from fixture windows.
  The test entry point bypasses normal startup and exits without installing
  the app or requesting permissions.
- `scripts/test_window_switcher.sh`: a signed Debug app, normally under 15 seconds,
  runtime budget 45 seconds. Requires an unlocked desktop with existing Accessibility
  and screen capture permissions. Checks the reveal delay, selection feedback in
  both preview modes, a real in-place preview, rapid selection changes, dismissal,
  key swallowing, the grave key moving the selection, its hotkeys being held
  only while the switcher is open, the quick-tap switch, and the ⌘Tab takeover.
  The ⌘Tab check is skipped while another Docky is running, and the grave key
  check with fewer than two windows or an action key bound to that key. Temporarily
  changed switcher preferences and the frontmost app are restored.

The integration checks validate native controller layout and lifecycle. They do not
replace interactive checks for drag sessions, auto-hide, VoiceOver, permission
grants, window-management actions, or physical display configurations. Verify those
in a running build, along with light/dark appearance, reduced motion, and reduced
transparency.

Before finalizing, run `git diff --check`, search app sources for SwiftUI imports and
hosting adapters, and inspect the main app and its app-owned helper binaries with
`otool -L` for SwiftUI linkage.

## Window switcher

The window switcher looks and behaves like the Windows 11 Alt+Tab switcher.
`WindowSwitcherController` centers an acrylic panel
(`WindowsTaskbarPopupChrome`) of window cards on the dock's screen.
`WindowSwitcherGeometry` gives every thumbnail one height (15% of the screen,
96–160 points), takes each card's width from its window's aspect ratio, and wraps
cards into centered rows at 85% of the screen width. Each card shows the app
icon and window title above the thumbnail, a 3-point selection frame in the
system accent color, and a close button on hover. Each thumbnail has a 1-point translucent border and a
soft drop shadow. Windows without a capture show their app icon, with neither.
"Switcher Font Size" (9–24 points, default 12) and "Switcher Icon Size" (12–48,
default 16) in Window Management size the title and icon. The header grows to
fit the larger of the two and never shrinks below 24 points.
The panel has a 1-point edge, stronger than taskbar popups, and a soft shadow.
Both shadows go through `NSView.shadow`, because AppKit resets a backing
layer's own shadow opacity.

Pressing and releasing the shortcut within 120 ms switches to the previous window
without showing the switcher. After that delay it appears at once and fades out
on dismissal. While it is open, Tab and the arrow keys move the
selection (↑ and ↓ follow the rows on screen), Delete closes the selected window,
Return or releasing the modifier switches, Escape or a click outside the panel
cancels, and every other key is swallowed so ⌘Q and ⌘H can't reach Docky.
As in macOS's ⌘Tab, ⇧Tab and the grave key (`` ` ``, above Tab on ANSI
keyboards) move back, and ⇧`` ` `` moves forward. Docky claims the grave key with
the shortcut's modifiers only while the switcher is open, so the key keeps its
usual meaning the rest of the time, such as ⌘`` ` `` cycling an app's windows.
A Close, Minimize or Zoom action bound to the grave key wins over moving back.

Like ⌘Tab, the switcher changes nothing until the shortcut is released.
"Enable Switcher Preview" in Window Management, off by default, adds a preview
of the selected window. In Place mode draws a live capture of the window at its
real position behind the panel after a 1-second hold. Instant Focus mode focuses
each selected window as you go.

In Instant Focus mode, selecting a window on another Space doesn't focus it,
because that would switch Spaces on every selection. The switcher stays visible
while such a window is selected, and releasing the shortcut switches to it.

The switcher and hover window previews list windows from every Space, including
fullscreen Spaces. "Show Windows From" in Window Management limits both to the
Spaces currently shown, like Windows 11's "Only on the desktop I'm using". The
app-folder "Windows" submenu always lists every Space. Actions that change
several windows at once (cycling or minimizing from a frontmost app's tile, and
tiling a folder's windows) act only on windows on the active Space.

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

`WindowsTaskbarStyle` defines Docky's only appearance. The bar spans the full
width of the bottom edge without rewriting the saved placement or tile order; it
lays out horizontally only, so other edges wait on a vertical layout. Start and
the app buttons sit on the bar, and most other tiles (folders, stacks, widgets)
live in the tray's overflow popup, styled by `WindowsTaskbarStyle.Tray`. Trash
has its own tray button: click to open it, right-click for its menu, and drop
files, folders, or apps on it to move them to the Trash. It highlights red while
it's the drop target and needs a drag source that allows moving. Running apps,
Docky itself, apps dragged out of an app folder, and drops in edit mode never go
to the Trash. Dragging a pinned taskbar button onto it unpins that app; a running
app's button stays while it runs. Dropping a Finder folder anywhere else on the
tray adds it to the overflow popup, just before Trash, and the overflow button
highlights while it's the drop target. The editor palette, Smart Organize, and
the macOS Dock import don't add spacers or dividers, since the taskbar never
draws them; saved ones still load but stay hidden.
Right-clicking empty taskbar space opens a menu with Activity Monitor, menu
extras, Settings, hiding, Edit Taskbar, Sync Dock, About, and Quit. The bar is 48
points tall by default, with 40-point buttons, 24-point icons, and 44-point pitch.
Dragging its top edge, or the Taskbar Size field in Settings, sets the height
from 32 to 96 points (`windowsTaskbarHeight`), and `WindowsTaskbarMetrics`
scales every button, icon, indicator, badge, and tray control with it. Native
menu extras keep their menu-bar size, so their slots grow but never shrink. Battery
details are available in the battery context menu. Status controls reflect Mac state and open Mac settings.

App insertion and removal use keyframes sampled from `Windows Taskbar Behavior.mov`
at source timestamps 11.742–12.033 and 14.175–14.408 seconds. The recording has
variable timestamps (1,090 source frames), so nominal 120-fps frame counts are not
used for timing. Icon entrance samples at 11.933–12.433 seconds reproduce the
delayed rise and damped bounce independently of recentering. Windows presentation
uses AppKit and Core Animation throughout.

The AppKit UI regression entry point includes taskbar geometry, the background
menu, the Taskbar Size setting, cancellation, and popup cleanup. To also write dark/light
rendering snapshots to `/tmp/docky-windows-snapshots`, add
`--windows-taskbar-snapshots` alongside `--appkit-ui-regression` when running a
previously built Debug app (30-second runtime budget). These snapshots do not
replace a desktop material, live motion, VoiceOver, or Windows VM comparison.
Segoe UI is used when installed; otherwise text uses the system font, whose glyph
shapes differ from Windows.
