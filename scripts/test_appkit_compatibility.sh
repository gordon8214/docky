#!/bin/bash
set -euo pipefail

# Expected under 10s. Bound compilation to 45s and the executable to 15s.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/docky-appkit-compatibility.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT

gtimeout 45 xcrun swiftc -swift-version 6 -parse-as-library \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -enable-upcoming-feature InferIsolatedConformances \
    "$project_root/Docky/Services/SettingsNavigationHistory.swift" \
    "$project_root/Docky/Models/WidgetKind.swift" \
    "$project_root/Docky/Models/WidgetSettings.swift" \
    "$project_root/scripts/tests/AppKitCompatibilityRegression.swift" \
    -o "$test_directory/compatibility-regression"
gtimeout 15 "$test_directory/compatibility-regression"
