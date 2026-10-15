# Windows taskbar menu extras

Menu extras have two states: native hosting or off. Use **Settings → Menu Extras →
Show Menu Extras**, or right-click the taskbar and toggle **Show Menu Extras**.
The checkbox in an extra's context menu controls the same saved setting.

Turning the setting off removes all menu extras, releases native hosts and popup
leases, stops discovery, and collapses their taskbar space. Turning it on discovers
visible macOS extras and hosts their original native scenes. Items that cannot be
hosted are omitted. There is no icon capture or image fallback, and menu extras do
not request Screen Recording permission. Battery, Volume, and Wi-Fi use the same
native hosts and setting; there are no separate Docky status-icon replacements.
The date/time control remains available independently. Saved Battery widgets remain
accessible through the additional Dock items menu.

## Native hosting

The setting is off by default and persists as `nativeMenuExtras`.
`--native-menu-extras` also enables it at launch.

The bridge currently targets this SIP-disabled Apple silicon Mac running
macOS 27.0.1 (26A434). Docky loads its signed `MenuBridge` payload into MenuBarAgent
and supported owning apps. No security setting is changed. Native slots preserve
the original item's width and only fully visible slots are hosted. Items that
cannot be hosted are omitted. No image is used while a host starts.
The agent confirms the matching layout before Docky treats an item as hosted.

AppKit extras use `NSStatusItemHost.createActiveReplicantView`. System extras use
an active `NSSceneHostingView` presentation of the existing system scene. Both
render in transparent, nonactivating panels over Docky's slots. There are no
captured pixels in a confirmed native slot. System scene layers need their native
center anchor restored while hosted; teardown restores the previous anchor before
deactivating and invalidating the presentation.

AppKit activation preserves the owner's native event path. Extras advertising an
expanded interface receive AppKit's native expanded-interface action. Other items
receive tagged native down/up events. The remote transport truncates event numbers
to signed 16-bit values, which the owner checks together with the persistent item
identifier. System scenes retain the original system item's AX action. Keyboard
and Accessibility activation publish the owner anchor before dispatching the
native action. Owner-side status-button and expanded-session hooks also recognize
physical activation over the leased Docky slot.

The owner supplies the original menus, windows, delegates, and controls:

- `NSMenu` uses its original menu object and AppKit popup API above the Docky slot.
- `NSPopover` uses its original object and an invisible owner-side positioning view
  at the Docky slot, with AppKit's arrow pointing down toward Docky.
- Custom status panels use their complete native window frame above the slot.
- Control Center keeps its original `ModuleWindow`. An ABI-checked frame hook
  applies the Docky placement to coordinator updates. Its accessible content bounds
  account for the large transparent backdrop, and placement updates as the native
  controls expand or collapse.

Existing document windows are excluded. An activation context lasts 1.5 seconds;
only new eligible status windows are attached. A short-lived owner tracking signal
holds Docky's autohide interaction while the original menu or popup is open.
Pointer hover and pending activation also hold the taskbar. Disabling the backend
or ending the lease closes attached popups and removes the agent's native panels.

Docky refreshes private mode-0600 requests every 200 ms with a three-second lease.
The payload rejects malformed, stale, future-dated, wrong-owner, or nonprivate
requests. Sandbox owners load the image from their own container's cache. Loader
success requires a real `dlopen` handle; load errors preserve original activation.
Content-addressed payloads are never overwritten while mapped. The payload stays
mapped until its process exits, but its windows and anchor behavior become inactive
when Docky's lease ends. Restart an affected owner or agent after changing the
bridge binary to compare implementations using fresh runtime classes.

### Live validation

Native system icons, including Control Center, rendered correctly. The original
full Control Center, Wi-Fi, and Sound popups opened above Docky. Wi-Fi
**Other Networks** and Sound device details expanded through the original controls;
placement followed the resulting height changes. Opening Wi-Fi details later
inside full Control Center also retained the Docky anchor.
Turning native hosting off removed the overlay panels and dismissed the system
popup while MenuBarAgent kept its PID.

The cross-process fixture in `DockyMenuBridge/Tests/PopoverFixture.m` verifies a
real `NSPopover` and a custom native panel. Both opened above Docky and their
original **Count** buttons changed from zero to one. The fixture also supports
`--popover-only`, `--custom-window-only`, and `--expanded-window-only` to avoid menu-bar overflow and
exercise the macOS 27 expanded-interface delegate path. Its original button
action worked, and quitting Docky invoked native session cancellation and removed
the agent overlays without restarting MenuBarAgent. It exits automatically after
ten minutes.

Syncthing's original `NSMenu` and BetterClaude Helper's original menu opened above
Docky. Selecting **About** opened the original **About Syncthing** window.

This remains an experiment. The loader receives a platform-binary library
validation rejection from Passwords Menu Bar Extra and Xcode Service on this Mac.
Their live icons and original activation remain available, but their popups retain
the original menu-bar anchor. Docky's native status reports that some owners keep
those anchors. Full physical-click, VoiceOver, autohide, light/dark, sleep/wake,
overflow, and multi-display qualification remains.

Focused checks (expected compilation under five seconds, runtime under one second;
the script enforces explicit limits):

```sh
scripts/test_native_menu_bridge.sh
```

They cover lease validation, malformed requests, replica identity, remote event
number truncation, popup geometry, private frame ABI, and agreement between the
loader's embedded bytes and its arm64e assembly source. The existing AppKit UI
regression harness also passes.

## Earlier AX popup placement investigation

The earlier prototype used an AX position request and independent readback. Before the owner bridge, Control Center returned
AX success but its coordinator reset the frame; the result was **Native host
rejected popup placement (AX 0)**. The native backend above now intercepts those
owner-side coordinator updates instead. The AX-only trial is no longer a taskbar option.

## Earlier standalone owner-side anchor experiments

The capture prototype was committed and pushed as `df8093f` before this investigation.
The standalone scripts below predate the bundled native backend described above.
They are separate from Docky's reservation bridge and only run when invoked.

On this Mac, the signed debugger probe obtained task ports for MenuBarAgent,
Control Center, and Syncthing. SIP was already disabled; this investigation did
not change it. Access here does not establish that injection will work on a
Mac with different security settings or for every hardened third-party owner.

The Syncthing proof retrieves its existing `NSMenu` from the owner's
`NSStatusBar` storage and presents that same object using AppKit's native popup
API at a supplied taskbar anchor. It does not copy the menu or replace its actions.
WindowServer reported the original owner and a menu frame `(901, 656, 170, 257)`;
the taskbar began at y=919, leaving a six-point gap above it. Selecting **About**
opened Syncthing's normal **About Syncthing** window. The menu reported a completed
selection. This establishes original-menu presentation and an original action;
it does not yet establish a general bridge for every owner or menu style.

The earlier temporary AppKit presentation hooks did not intercept this owner's
normal opening path and restored themselves. The retained proof installs no
persistent hooks. It requires exactly one distinct status menu in the owner;
multiple-menu owners need explicit item selection.

Control Center uses `ControlCenterApp.ModuleWindow` with a SwiftUI hosting view.
Owner-side `NSWindow.setFrame` immediately accepted the requested frame
`(1018, -349, 656, 962)` in Cocoa coordinates, but after one second the native
coordinator had reset it to `(1016, 5, 656, 962)`. The experiment then explicitly
restored that original frame. A successful setter inside the owner is therefore
insufficient for sustained popover placement.

Runtime metadata identifies `ControlCenterApp.MenuPositionCoordinator`, with
`anchor`, `window`, `anchorObservationTask`, `menuFrame`, and `bentoBoxFrame` fields.
Its `SimpleMenuAnchor` has a CGRect `_frame`, `_screen`, `_anchorView`, and an
Observation registrar. Those Swift anchor updates are the next hook boundary.
Blindly writing the backing rectangle would bypass Observation and is not a
validated solution. The live probe records metadata without doing such writes.

Reproduce on this Apple silicon development Mac with Docky running and the
corresponding tray button visible. Use the same authorized development signing
identity as the app. Expected compilation is under ten seconds; each AX request
and injection is bounded. The default command only builds tools:

```sh
DOCKY_MENU_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" scripts/experiment_menu_owner_anchor.sh build
DOCKY_MENU_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" scripts/experiment_menu_owner_anchor.sh access
DOCKY_MENU_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" scripts/experiment_menu_owner_anchor.sh open-menu
# Open the original Control Center first. This trial restores its frame after one second.
DOCKY_MENU_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" scripts/experiment_menu_owner_anchor.sh move-control-center
```

Results are written to `build/MenuOwnerExperiment/report.log`. Requests are
owner/PID-bound, expire after sixty seconds, and require a regular file owned by
the current user with mode 0600. Payloads remain mapped until their owner exits;
the menu proof has no active behavior after its native menu closes. The loader
copies are built for these two explicit owners; the production Dock-only loader
is unchanged.

## Validation

The Debug AppKit UI harness checks negative/offset display geometry, popup edge
clamping and transparent backdrop offsets, plus the native-only toggle. It verifies
that the settings checkbox controls the shared saved preference, taskbar changes
update that checkbox, and the off state clears hosts and occupies no extra space.
The suite runs in about four to eight seconds, with a 30-second limit:

```sh
scripts/test_appkit_ui.sh
```

An additional Debug-only, read-only probe has a ten-second runtime budget:

```sh
gtimeout 10 build/AppKitDerivedData/Build/Products/Debug/Docky.app/Contents/MacOS/Docky \
  --menu-extras-probe --popup-diagnostics \
  -ApplePersistenceIgnoreState YES
```

The probe checks AX and event-post access and reports item frames. A
shell launch can inherit the shell host's grants; it does not prove that a
Finder-launched app has its own permissions. Use a consistent development signing
identity for interactive testing. Ad-hoc signatures change the code requirement
between builds, and macOS Settings can refer to an older registered app copy.

Architecture references: [Pelmet's macOS 27 item discovery](https://github.com/fif7y/pelmet/blob/main/Packages/PelmetEngine/Sources/PelmetEngine/ItemEnumerator.swift)
and [Ice's capture/click implementation](https://github.com/jordanbaird/Ice/tree/main/Ice/MenuBar/MenuBarItems).
