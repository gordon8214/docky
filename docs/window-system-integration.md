# Window system integration

Docky uses the actual Dock window level and a nonactivating panel. Managed
display Spaces determine fullscreen and Split View independently of
Accessibility permission. Entry immediately clears transient interaction state
and dismisses passive Dock-attached presentations. A deliberate edge dwell can
reveal Docky over fullscreen content; explicit keyboard launchers and switchers
retain their own presentation behavior.

Fixed Docky reserves the resting chrome's depth across its screen edge,
including any edge gap. Magnification headroom and expanded presentations do
not increase this reservation. Autohide and fullscreen reserve nothing, even
during a temporary reveal. Layout reads physical screen bounds and the display
menu-bar height, never its own reduced `NSScreen.visibleFrame`. Top placement
retains menu-bar clearance.

## Private ABI verified on macOS 27.0.1 (26A434)

The signatures and notification packet were checked against this OS's Dock and
SkyLight binaries, then tested with an independent AppKit process.

| Contract | Value |
| --- | --- |
| Setter | `SLSSetDockRectWithOrientation(int connection, CGRect rect, int reason, int orientation)`; rectangle by value |
| Getter | `SLSGetDockRectWithOrientation(int connection, CGRect *rect, int *reason, int *orientation)` |
| Fixed reservation | Reason `0` |
| No reservation | Reason `2`, zero rectangle |
| Orientation | Top `1`, bottom `2`, left `3`, right `4` |
| Coordinates | Quartz desktop coordinates, with top-left origin relative to the primary display |
| Geometry notification | Dock-origin broadcast `1201`; four `float` coordinates, then 32-bit reason and orientation; 24 bytes |
| Menu-bar clearance | `SLSGetDisplayMenubarHeight`; top reservation is additional to this clearance |
| Fullscreen and Split View | Current managed display Space type `4`; ordinary/system types `0`/`2` |

Private functions are dynamically loaded. Float normalization prevents repeated
publication of fractional-point geometry. Space declarations follow
[yabai's declarations](https://raw.githubusercontent.com/asmvik/yabai/master/src/misc/extern.h).

## Dock-side publisher

Direct publication succeeds on this OS, and a fresh AppKit process sees the
correct usable area. However, Apple Dock overwrites it during layout updates,
and existing AppKit clients need a Dock-origin notification. WindowManager also
maintains a separate tiling inset cache. Consequently the production backend
probes direct publication, then loads the bundled Dock-side publisher.
The probe snapshots and restores Apple's reservation synchronously before
loading the helper, so rejected authorization cannot leave probe geometry behind
or contaminate the payload's restoration snapshot.

The payload intercepts the Objective-C adapter
`setDockInfoWithDisplayID:currentInset:maximumInset:orientation:` in Apple's Dock
or WindowManager image. Dock calls it immediately after its own rectangle
publication. The payload substitutes Docky's rectangle, emits the geometry
notification, and calls the original adapter with the matching inset in that
same main-thread operation. Display movement clears the previous display's
tiling inset. This does not patch executable or protected binding pages.
Apple callbacks for other displays are forwarded, with separate rollback
snapshots for each display. A later valid adapter callback recovers a missed
initial coordinator lookup.

Injection happens after Dock's initial layout. On this OS Dock uses a Carbon
loop, with no `NSApp.delegate`. The payload locates the already-live Swift
`DockCore.DockAgent` in the executable's writable globals or main-loop stack,
using the runtime ISA mask and checked Mach reads for candidate pointers. This
read-only search has a half-second budget. The runtime-described `expose` ivar
then provides the existing adapter. Failure to find it rejects the backend;
usable-frame readback alone must not conceal a missing tiling coordinator.

The loader is adapted from [yabai's MIT-licensed Dock injection
loader](https://raw.githubusercontent.com/asmvik/yabai/master/src/osax/loader.m).
Its license and attribution are bundled. The loader and payload contain
`arm64e` and `x86_64` slices; the main app contains `arm64` and `x86_64` slices.
Injection requires the system's task-port/debugger authorization and compatible
SIP configuration. This host already had SIP disabled; validation did not
change system security settings. The loader carries the debugger entitlement.

The user-only Unix socket authenticates kernel-reported UID/PID and the signed
Docky code identifier. Requests also require the active owner PID and session
from Docky's private visibility-state file. Serialized revisions reject stale
updates. IPC is length-prefixed, size-limited, and bounded by timeouts, including
nonblocking connection attempts. The
payload validates display geometry and process start identity against PID reuse.

A main-thread lease releases the reservation when its owner exits, its session
disappears, or Docky marks reservation ownership inactive after a backend
failure. The existing independent watchdog preserves/restores Apple's original
Dock preferences and restarts Dock after an unexpected owner exit. Docky
reconnects after Apple Dock restarts. Backend and independent readback failures
appear in Settings → Behavior → System Dock and feedback diagnostics; an
explicit retry is available. There is no Accessibility resize fallback.

## Regression commands

Build Debug first. Live bridge tests require a signed app. For a local unsigned
development build, ad-hoc sign it while preserving the loader entitlement:

```sh
codesign --force --deep --sign - --preserve-metadata=entitlements \
  build/AppKitDerivedData/Build/Products/Debug/Docky.app
scripts/test_dock_payload.sh
scripts/test_dock_system.sh
scripts/test_dock_bridge.sh
gtimeout 30 python3 scripts/test_dock_lifecycle.py
scripts/test_appkit_ui.sh
scripts/test_appkit_browser.sh
scripts/test_appkit_compatibility.sh
```

Quit a running production Docky before live bridge/lifecycle tests. Focused
regressions should finish within approximately 10 seconds; AppKit/lifecycle
regressions within approximately 15 seconds. Executables are capped at 30
seconds or less. Standalone AppKit harness compilation has a separate 45-second
budget. Live tests temporarily restart Apple Dock and restore its preferences.
Regression launches ignore saved-window restoration for that process only, so
intentional crash fixtures cannot block later runs on AppKit's recovery dialog.

Coverage includes managed Space classification, real window level, stale
interaction clearing, legacy preference/profile migration, edge-gap and
magnification geometry, negative/offset display coordinates, all four native
reservation orientations, independent AppKit readback, real fullscreen entry
and exit, authenticated/stale IPC, helper-failure release, Dock restart, and
forced-termination watchdog recovery. Focused payload tests exercise synthetic
cross-display callbacks and late coordinator recovery without injection. Loader
fault-injection tests verify setup-failure cleanup using mocked Mach operations. System
tests cover reserved-edge display selection, full socket backlogs, direct-probe
rollback on loader failure, and stale interaction-token release. Dock-attached
profile and progress panels follow hidden/revealed state; keyboard panels retain
their separate presentation lifecycle.

An already-running independent AppKit window was also verified to receive the
Dock-origin notification: a 70-point bottom reservation changed its usable
frame and zoomed frame from 939 to 869 points high. Applications that choose to
ignore usable screen bounds can overlap this Dock, as with Apple's Dock.

Live production validation also confirmed a 52-point resting chrome at native
window level 20. Finder's zoom and Fill ended exactly at its upper edge. The
independent AppKit window exercised the native Fill, Left Half, and Bottom Right
Quarter actions; all stayed inside the reduced usable area. These actions are
included in the bridge regression, with a separate five-second subprocess
budget. The fixture launches before publication and retains its window, so the
check also covers native tiling in an already-running client. Normal quit and
forced termination restored the original usable area.

The host exposes one physical display. Physical display movement and full
manual Split View pairing still require additional verification. Geometry
tests cover offset displays but do not substitute for that hardware
verification. Desktop capture initially failed, then became available for a
new Finder window; native menu actions and window geometry were checked live.
