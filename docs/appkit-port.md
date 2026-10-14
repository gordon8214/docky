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
  target rejection, Launchpad page geometry, search keys, and controller release.
- `scripts/test_appkit_compatibility.sh`: compilation 45 seconds, runtime 15 seconds.
  Covers Settings history and legacy widget kind, span, and opaque-settings encoding.
- `scripts/test_appkit_ui.sh`: a previously built Debug app, runtime 30 seconds;
  normally under 15 seconds. Exercises every Settings pane twice, built-in and
  legacy widget spans, compact/expanded layout, canceled drag mouse-up, and observer
  release. Also covers isolated Launchpad folder mutations and drop indexes,
  grid keyboard navigation, dismissed folder callbacks, file context menus,
  calendar dates, denied-permission controls, initial lyric scrolling, widget reuse,
  badge limits, and cached Hidden Apps updates.
  The test entry point bypasses normal startup and exits without installing
  the app or requesting permissions.

The integration checks validate native controller layout and lifecycle. They do not
replace interactive checks for drag sessions, magnification, auto-hide, VoiceOver,
permission grants, window-management actions, or physical display configurations.
Verify those in a running build, along with themes, light/dark appearance, reduced
motion, and reduced transparency.

Before finalizing, run `git diff --check`, search app sources for SwiftUI imports and
hosting adapters, and inspect the main app and its app-owned helper binaries with
`otool -L` for SwiftUI linkage.
