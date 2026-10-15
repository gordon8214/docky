<div align="center">

<img src="docs/images/logo.png" width="128" alt="Docky logo">

# Docky

### Native AppKit Dock for macOS 27

Docky is a Dock replacement for macOS that elegantly replaces the system one. It
brings the Dock back into reach: quieter, smarter, and native-feeling, with a
configurable layout, widgets, a fullscreen Launchpad, a live window switcher,
custom icons, and scripted actions.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/macOS-27%2B-black?logo=apple)](https://getdocky.com)
[![Apple silicon](https://img.shields.io/badge/Apple%20silicon-arm64-orange)](https://getdocky.com)
[![Website](https://img.shields.io/badge/getdocky.com-Download-brightgreen)](https://getdocky.com)
[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-ea4aaa?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/josejuanqm)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-ffdd00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/josejuanqm)
[![Discord](https://img.shields.io/badge/Discord-join-5865F2?logo=discord&logoColor=white)](https://discord.gg/vAwVNtPSgE)

[**Download**](https://getdocky.com) &nbsp;·&nbsp; [**Website**](https://getdocky.com) &nbsp;·&nbsp; [**Build from source**](#building-from-source)

</div>

<div align="center">
  <img src="docs/images/hero.jpg" alt="Docky on macOS" width="900">
</div>

## Why Docky

The Dock is the most-used surface on a Mac, and it has barely changed in years.
Docky rebuilds it for focus: it can run alongside, mirror, or fully replace the
system Dock, and it moves with your workflow instead of getting in the way.

- **Free and open source.** No paid tier, no upsell. Licensed under GPLv3.
- **Native-feeling.** Built for Apple silicon, notarized by Apple.
- **Yours to shape.** Pin what you reach for, arrange it how you think, and drop
  in widgets and actions that match how you work.

## Features

### Tiles and layout

Docky draws a Windows 11–style taskbar. The Start button and your apps sit on the
bar, and folders, stacks, widgets, and Smart Stacks live in the tray. Pin what you
reach for, drag to reorder, and resize the bar from its top edge.

<div align="center"><img src="docs/images/feature-layout.jpg" alt="Tiles and layout" width="820"></div>

### Window switcher, live

A global, Cmd-Tab-style window switcher with live window previews, plus per-tile
hover previews so you can see a window before you raise it.

<div align="center"><img src="docs/images/feature-window-switcher.jpg" alt="Live window switcher" width="820"></div>

### Built-in Launchpad

A fullscreen, searchable app launcher with full keyboard navigation, its own
layout, and an optional global shortcut.

<div align="center"><img src="docs/images/feature-launchpad.jpg" alt="Built-in Launchpad" width="820"></div>

### Widgets in the tray

Built-in widgets (Calendar, Reminders, Batteries, System, Weather, Now Playing,
and more) live in the taskbar's tray. Stack several into a single tile with **Smart
Stacks** and cycle through them in place. This fork supports built-in widgets only.
Saved community widgets appear as removable unsupported placeholders; their settings
and placements are preserved, and installed bundles remain on disk.

<div align="center"><img src="docs/images/feature-widgets.jpg" alt="Widgets and Smart Stacks" width="820"></div>

### Rich app folders

Group apps into folders with nested navigation, Quick Look, and drag-and-drop.
Optionally show running apps inline so a folder doubles as a live workspace.

<div align="center"><img src="docs/images/feature-folders.jpg" alt="Rich app folders" width="820"></div>

### More

- **Custom app icons:** override the icon for any pinned, running, or
  widget-backed app.
- **Scripted actions:** catalog-backed AppleScript and menu-click automation,
  plus curated commands.
- **Profiles:** switchable configuration profiles.

## Upstream downloads

The links below distribute upstream Docky. Build this AppKit fork from this checkout
using the instructions below. Sparkle and its existing update configuration are retained.


Get the latest notarized build from [getdocky.com](https://getdocky.com), or grab
a release from the [Releases page](https://github.com/josejuanqm/docky/releases).

### Homebrew

```sh
brew install --cask josejuanqm/tap/docky
```

Updates are delivered in-app via Sparkle. No tap trust step is needed for a normal
install. If you run Homebrew with `HOMEBREW_REQUIRE_TAP_TRUST=1`, trust the cask
first with `brew trust --cask josejuanqm/tap/docky`.

Docky needs **Accessibility** and **Screen Recording** permissions to manage
windows and render previews. It prompts for these on first launch.

> [!NOTE]
> Docky uses private SkyLight / CoreGraphics Services and Accessibility SPI (see
> `Docky/Private/`) to position windows, capture previews, and drive the system
> Dock. Because of this, **Docky cannot be distributed on the Mac App Store**.
> It is built from source or distributed directly.

## Building from source

```sh
git clone https://github.com/josejuanqm/docky.git
cd docky
open Docky.xcodeproj
```

Build and run the `Docky` scheme. Swift Package dependencies (Sparkle) resolve
automatically on first build.

### Requirements

- macOS 27 or later
- Xcode with the macOS 27 SDK

## Documentation

- [AppKit implementation and validation](docs/appkit-port.md)
- [Legacy community widget compatibility](docs/external-widgets.md)

## Supporting Docky

Docky is free and open source with no paid tier. If it earns a place in your
Dock, you can help fund ongoing development:

- **[GitHub Sponsors](https://github.com/sponsors/josejuanqm)**: one-time or
  monthly, with tiers from ☕ Coffee to ❤️ Patron.
- **[Buy Me a Coffee](https://buymeacoffee.com/josejuanqm)**: a quick one-off
  thank-you.

Sponsors also get a supporter role in the [Docky Discord](https://discord.gg/vAwVNtPSgE).
Supporters are credited in [SUPPORTERS.md](SUPPORTERS.md); sponsoring teams can
have their logo featured there. Every bit helps keep Docky maintained and free.

## Dependencies

- [Sparkle](https://github.com/sparkle-project/Sparkle): software update
  framework (BSD 3-Clause).

## License

[GNU General Public License v3.0](LICENSE). Copyright (C) 2026 Jose Quintero.
