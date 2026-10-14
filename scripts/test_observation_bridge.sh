#!/bin/bash
set -euo pipefail

# macOS-only check using the project's Xcode toolchain. Expect under 10 seconds;
# bound compilation to 30 seconds and the regression executable to 10 seconds.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/docky-observation-test.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT

gtimeout 30 xcrun swiftc -swift-version 6 -parse-as-library \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -enable-upcoming-feature InferIsolatedConformances \
    "$project_root/Docky/Services/ObservationBridge.swift" \
    "$project_root/scripts/tests/ObservationBridgeRegression.swift" \
    -o "$test_directory/observation-regression"
gtimeout 10 "$test_directory/observation-regression"
