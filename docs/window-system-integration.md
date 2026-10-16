# Window system integration

Docky uses the actual Dock window level and a nonactivating panel. Managed
display Spaces determine fullscreen and Split View independently of
Accessibility permission. Entry immediately clears transient interaction state
and dismisses passive Dock-attached presentations. A deliberate edge dwell can
reveal Docky over fullscreen content; explicit keyboard launchers and switchers
retain their own presentation behavior.

Fixed Docky reserves the resting chrome's depth across its screen edge. The
taskbar sits flush against that edge, so there is no edge gap;
`DockSystemGeometry.restingChrome(edgeGap:)` keeps the parameter, which only the
regression exercises. Expanded presentations do not increase this reservation.
Autohide and fullscreen reserve nothing, even during a temporary reveal. Layout
reads physical screen bounds and the display menu-bar height, never its own
reduced `NSScreen.visibleFrame`. Top placement retains menu-bar clearance once
the taskbar supports other edges. While the Windows taskbar's top edge is
dragged, the bar resizes without publishing; the new reservation is published
once, when the drag ends.

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
Its license and attribution are bundled. The loader and payload contain only
`arm64e`; the main app and watchdog contain only `arm64`. Docky supports Apple
silicon Macs. Vendor frameworks retain their supplied architectures.
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
appear in Settings → General → System Dock; an explicit retry is available. There is no Accessibility resize fallback.

## Window list and thumbnails

`WindowRegistry` reads other apps' windows from WindowServer, not from
Accessibility. `kAXWindowsAttribute` only returns windows on the active Space,
plus minimized windows and hidden apps' windows. On a Mac with four Spaces it
returned 2 of 19 user windows. None of the calls below needs SIP disabled or
the Dock-side publisher. `Docky/Private/WindowServerWindows.swift` loads them,
and `Docky/Services/WindowServerWindowRules.swift` interprets their values.

| Contract | Value (macOS 27.0.1, 26A434) |
| --- | --- |
| Spaces | `SLSCopyManagedDisplaySpaces`; `Current Space` is each display's visible Space |
| Windows per Space | `SLSCopyWindowsWithOptionsAndTags(connection, 0, [space], 0x7, &1, &0)`; option `0x7` includes minimized windows |
| Window details | `SLSWindowQueryWindows` iterator: parent, level, PID, tags, attributes, bounds |
| User windows | Parent `0`, level `0`, and yabai's document-tag rule; bounds match `kCGWindowBounds` |
| Minimized | Tag bit `0x1000000000000000`; the window is ordered out but keeps its Space |
| Listed | Ordered in (`SLSWindowIsOrderedIn`) or minimized; other ordered-out windows are windows the app closed but kept |
| Native tabs | Only the selected tab belongs to a Space, matching Mission Control |
| Titles | `kAXTitleAttribute` first; otherwise `kCGWindowName` from `CGWindowListCreateDescriptionFromArray`, which needs Screen Recording |
| Capture | `SLSHWCaptureWindowList(connection, &id, 1, options)`; `1 << 11` ignores the global clip shape, `1 << 9` returns points, `1 << 8` returns backing pixels |
| AX elements on other Spaces | `_AXUIElementCreateWithRemoteToken`: PID, 4 zero bytes, `0x636f636f`, then a 64-bit element ID. Window element IDs were below 1,000 in testing (highest seen: 325), so the scan stops at 1,000 |

Callers check Screen Recording permission before capturing. Capture takes
30–50 ms per window and works for windows on inactive Spaces,
minimized windows and hidden apps' windows. ScreenCaptureKit failed on some
of those, and on every window of an unsigned test app on another Space. The
live focus preview still streams through ScreenCaptureKit for windows on the
active Space, and polls SkyLight captures for the rest.

Cached thumbnails are never evicted while their window exists.
`WindowPreviewRefreshQueue` captures windows without a thumbnail first, then
thumbnails invalidated by a resize or focus change, then stale ones (older than
120 s or retitled). Stale refreshes start at most every 500 ms, and each
window's at most every 5 s, so the old image shows until its replacement
arrives.

Connection notifications, registered with `SLSRegisterConnectionNotifyProc`,
arrive on the main thread while AppKit pumps events. Window events need
`SLSRequestNotificationsForWindows` for the window first. Each request replaces
the previous set, and requests for more than 1,024 windows fail.

| Event | Packet | Fires when |
| --- | --- | --- |
| `804` | window ID | A requested window is destroyed |
| `806` / `807` | window ID | A requested window moves / resizes |
| `815` / `816` | window ID | Both fire when a requested window is minimized or restored |
| `1325` / `1326` | 64-bit Space ID, window ID | Any window joins / leaves a Space; how new and closed windows are found |

No WindowServer event reports title changes, app hiding, or a tab switch in a
background app. The registry takes titles and focus order from AX
notifications, and hiding from `NSWorkspace`. A tab switch in the active app
changes its focused window, which refreshes the list.

A new window goes first in the list when it has focus and second, behind the
current window, when it doesn't (`WindowRecencyOrder`). Only the frontmost
app's focus changes reorder the list: a background app's new window becomes
that app's focused window without being used, and moves first when the app
activates (`NSWorkspace.didActivateApplicationNotification`). A launching app
usually focuses its first window before Docky installs the app's AX observer,
so that focus change sends no notification. When a snapshot first lists a
window of the frontmost app, or Docky has just started observing that app, the
registry reads the app's focused window from AX instead.

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
scripts/test_window_registry.sh
scripts/test_appkit_browser.sh
scripts/test_appkit_compatibility.sh
```

Sign local Release builds before launching them too. `CODE_SIGNING_ALLOWED=NO`
leaves a linker signature with identifier `Docky`, which does not authenticate
as `gt.quintero.Docky`. The Dock-side publisher rejects that build and releases
the screen reservation. Settings → General → System Dock displays the error.
After signing, use Retry or relaunch Docky. Verify the bundle with
`codesign --verify --deep --strict` before running it.

Quit a running production Docky before live bridge/lifecycle tests. Focused
regressions should finish within approximately 10 seconds; AppKit/lifecycle
regressions within approximately 15 seconds. Executables are capped at 30
seconds or less. Standalone AppKit harness compilation has a separate 45-second
budget. Live tests temporarily restart Apple Dock and restore its preferences.
Regression launches ignore saved-window restoration for that process only, so
intentional crash fixtures cannot block later runs on AppKit's recovery dialog.

Coverage includes managed Space classification, real window level, stale
interaction clearing, legacy preference/profile migration, edge-gap geometry,
negative/offset display coordinates, all four native
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
