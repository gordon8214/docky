#!/bin/bash
set -euo pipefail

# Expected: under 15 seconds after SDK caches are warm. Compile budget: 45s; run: 15s.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/docky-appkit-test.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT

gtimeout 45 xcrun swiftc -swift-version 6 -parse-as-library \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -enable-upcoming-feature InferIsolatedConformances \
    "$project_root/Docky/Services/DockAxisGeometry.swift" \
    "$project_root/Docky/Services/DockDropGeometry.swift" \
    "$project_root/Docky/Services/DockPresentationGeometry.swift" \
    "$project_root/Docky/Services/WindowPreviewCaptureSupport.swift" \
    "$project_root/Docky/Views/AppKit/DockWindowInteraction.swift" \
    "$project_root/Docky/Views/AppKit/NativeControls.swift" \
    "$project_root/Docky/Views/AppKit/NativeObservationSession.swift" \
    "$project_root/Docky/Views/AppKit/NativeBrowserController.swift" \
    "$project_root/Docky/Views/AppKit/NativeBrowserController+DataSource.swift" \
    "$project_root/Docky/Views/AppKit/NativeLaunchpadGridLayout.swift" \
    "$project_root/Docky/Views/Tiles/ContextActionPopover.swift" \
    "$project_root/scripts/tests/AppKitBrowserRegression.swift" \
    -o "$test_directory/appkit-regression"
gtimeout 15 "$test_directory/appkit-regression"
