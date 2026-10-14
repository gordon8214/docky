#!/bin/bash
set -euo pipefail

# macOS-only regression check. Expect under 10 seconds; bound compilation
# to 30 seconds and the executable (including delayed rescans) to 10 seconds.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/docky-launchpad-test.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT

gtimeout 30 xcrun swiftc -swift-version 6 -parse-as-library \
    -warnings-as-errors \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -enable-upcoming-feature InferIsolatedConformances \
    "$project_root/Docky/Models/LaunchpadLayout.swift" \
    "$project_root/Docky/Services/LaunchpadOverlayService.swift" \
    "$project_root/scripts/tests/LaunchpadScanRegression.swift" \
    -o "$test_directory/launchpad-regression"
gtimeout 10 "$test_directory/launchpad-regression"
