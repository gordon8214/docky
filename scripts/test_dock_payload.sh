#!/bin/bash
set -euo pipefail
# Expected under 5 seconds to compile, under 1 second to run; caps 30s and 10s.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
probe_dir="$(mktemp -d /tmp/docky-payload-tests.XXXXXX)"
trap 'rm -rf "$probe_dir"' EXIT
gtimeout 30 xcrun clang -fobjc-arc -mmacosx-version-min=27.0 -Wall -Wextra \
    -framework AppKit -framework Security \
    "$project_root/DockyDockBridge/Tests/payload_regression.m" -o "$probe_dir/payload-regression"
gtimeout 10 "$probe_dir/payload-regression"
gtimeout 30 xcrun clang -mmacosx-version-min=27.0 -Wall -Wextra -framework Cocoa \
    "$project_root/DockyDockBridge/Tests/loader_regression.m" -o "$probe_dir/loader-regression"
if ! gtimeout 10 "$probe_dir/loader-regression" > "$probe_dir/loader.log" 2>&1; then
    cat "$probe_dir/loader.log"
    exit 1
fi
gtail -1 "$probe_dir/loader.log"
