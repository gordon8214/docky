# Windows taskbar menu extras

The Windows theme displays captured macOS menu-extra icons in its right-side tray.
These are the original icons, not application-icon substitutes. The existing
Windows date/time display remains, and Docky's own status item is excluded.
Captured Wi-Fi, Sound, and Battery items replace the corresponding fallback buttons.

## Operation

Discovery walks MenuBarAgent's Accessibility tree on an actor with bounded AX calls.
It collapses the duplicates exposed by navigation and rendering windows, keeps each
display's items separate, and ignores frames outside the visible menu-bar band.
ScreenCaptureKit keeps one stream per display capturing only that band, without the
pointer or audio. A continuing stream keeps the recording indicator from repeatedly
reflowing the menu bar. Discovery is sampled again after capture starts, and icons
refresh every ten seconds while a Windows taskbar view is attached. Frame requests
have a three-second deadline and ignore late or duplicate completion and detached
views. Streams stop when the last taskbar view detaches.

Flat captured backgrounds are removed. Monochrome glyphs adapt to the taskbar's
appearance; colored status indicators retain their color. Nonuniform backgrounds
are preserved. Wide custom graphs/text are scaled into the prototype's icon slots.
The tray scrolls if its icons exceed the available width. Hidden macOS extras are
not automatically revealed or moved out of macOS's own overflow area.

Clicking uses the original item's Accessibility action or its current physical
menu-bar hit target. Third-party items have a physical-click fallback with a complete
down/up pair. The prototype retains the original menus and popovers at their native
anchors. Right-click an icon for **Try Native Popup Above Dock** and the last result.

## Native popup investigation

The placement experiment records existing windows before activation. It considers
only a new popup belonging to that item or its system host near the original icon.
It uses the popup's visible Accessibility controls to account for large transparent
backdrops, requests a new position above the tray, and independently verifies both
AX and WindowServer positions after the request. Failed or canceled moves restore
the original position. Existing document windows are excluded.

On macOS 27.0.1 (26A434), the original Control Center opens from the tray. Its window
reports a writable AX position, and setting it returns AX success. Nevertheless,
the native host keeps the original position. Live readback confirmed both AX and
CG bounds remained `(1016, 0, 656, 962)` after the placement attempt. Much of that
rectangle is a transparent backdrop; its actual controls occupy a smaller region.
The result is **Native host rejected popup placement (AX 0)**. Original popup
placement above the dock has therefore not been achieved.

Local runtime inspection found `MBMenuBarItemManager` methods for menu tracking
and locking menu position. `MBTriggerActionContext` exposes source/context IDs;
the inspected Objective-C surface provides no arbitrary popup anchor argument.
This does not establish that relocation is impossible. The next avenue is a
MenuBarAgent or owner-side bridge that changes the native tracking/popover anchor.
The current Apple Dock reservation bridge targets a different process and purpose.
Moving only rendered pixels would not establish correct native hit testing.

Third-party click forwarding is implemented, including a correction for hosted
items that reject a direct AX press. Control Center activation was verified live;
Syncthing forwarding returned success in the final live run. A ChatGPT hosted-item
press returned `AX cannotComplete`; the prototype reports that failure and does not
send a second click that could dismiss a menu opened by a timed-out AX request.
All third-party menu styles, VoiceOver navigation, dark appearance, and multiple
physical displays still need broader interactive qualification.

## Validation

The Debug AppKit UI harness includes negative/offset display geometry, Retina crop
coordinates, popup edge clamping and transparent backdrop offsets, capture
cancellation before registration, late completion, backdrop transparency, and
colored-indicator preservation. It runs in
about four to eighteen seconds, with the existing 30-second limit:

```sh
scripts/test_appkit_ui.sh
```

An additional Debug-only, read-only probe has a ten-second runtime budget:

```sh
gtimeout 10 build/AppKitDerivedData/Build/Products/Debug/Docky.app/Contents/MacOS/Docky \
  --menu-extras-probe --capture-menu-extras --popup-diagnostics \
  -ApplePersistenceIgnoreState YES
```

The probe checks AX, capture, and event-post access and reports item frames. A
shell launch can inherit the shell host's grants; it does not prove that a
Finder-launched app has its own permissions. Use a consistent development signing
identity for interactive testing. Ad-hoc signatures change the code requirement
between builds, and macOS Settings can refer to an older registered app copy.

Architecture references: [Pelmet's macOS 27 item discovery](https://github.com/fif7y/pelmet/blob/main/Packages/PelmetEngine/Sources/PelmetEngine/ItemEnumerator.swift)
and [Ice's capture/click implementation](https://github.com/jordanbaird/Ice/tree/main/Ice/MenuBar/MenuBarItems).
