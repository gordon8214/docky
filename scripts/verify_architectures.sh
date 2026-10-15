#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /path/to/Docky.app" >&2
    exit 64
fi
app_path="$1"

# Vendor frameworks retain their original binaries and signatures.
verify_binary() {
    local binary="$app_path/$1"
    local expected="$2"
    local actual
    if [[ ! -f "$binary" ]]; then
        echo "Missing project-owned binary: $binary" >&2
        return 1
    fi
    actual="$(xcrun lipo -archs "$binary")"
    if [[ "$actual" != "$expected" ]]; then
        echo "Unexpected architectures in $binary: $actual (expected $expected)" >&2
        return 1
    fi
    echo "$1: $actual"
}

verify_binary "Contents/MacOS/Docky" arm64
verify_binary "Contents/Library/LoginItems/DockyDockWatchdog.app/Contents/MacOS/DockyDockWatchdog" arm64
verify_binary "Contents/Resources/DockBridge/DockyDockLoader" arm64e
verify_binary "Contents/Resources/DockBridge/DockyDockBridge.dylib" arm64e

verify_binary "Contents/Resources/MenuBridge/DockyMenuLoader" arm64e
verify_binary "Contents/Resources/MenuBridge/DockyMenuBridge.dylib" "arm64 arm64e"
