---
name: install-docky
description: Build the current Docky checkout in Release, quit existing Docky copies, replace /Applications/Docky.app, and launch the installed copy. Use when asked to install, reinstall, or refresh Docky on the local Mac.
---

# Install Docky

From the repository root, run:

```bash
.agents/skills/install-docky/scripts/install.sh
```

The script builds the `Docky` scheme in `Release` with the project's signing settings, verifies the app and embedded binaries, quits all running Docky copies, replaces `/Applications/Docky.app`, and launches that exact bundle. It resolves the checkout from its own location, so it also works from another working directory.

- Run this installer directly; its Release build provides build validation. Avoid concurrent Xcode builds against the same DerivedData directory.
- Preserve signing and entitlements. Resolve build failures before installing; never substitute a stale build or disable signing.
- The existing app stays in place until the new bundle is staged and verified. The installer restores it if replacement or installed signature verification fails.
- Quit Docky normally first so it can restore the system Dock. Wait for its watchdog to exit before replacing the bundle; do not kill the macOS Dock yourself.
- Preserve preferences, permissions, and user data. Replace only `/Applications/Docky.app`; leave app bundles in other directories alone after quitting them.
- If `/Applications` is not writable, report the failure instead of silently changing the destination.

For an explicitly requested build without installation or launch:

```bash
.agents/skills/install-docky/scripts/install.sh --build-only
```

Allow about ten minutes for a first Release build: run the installer in the background, or with a timeout that covers that estimate, and poll it with short waits. If it exceeds that estimate, inspect the build log and active compiler/package-resolution processes before continuing.

Report build, installation, and launch separately. On success, include `/Applications/Docky.app` and the verified launched PID. Launch verification confirms the process path; it does not prove permission-dependent Dock behavior or UI interactions.
