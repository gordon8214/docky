#!/bin/bash
set -euo pipefail
# Expected under 10 seconds once macOS debugger authorization is granted.
# Budget: 30 seconds. Requires a signed Debug app and a WindowServer session.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_binary="${1:-$project_root/build/AppKitDerivedData/Build/Products/Debug/Docky.app/Contents/MacOS/Docky}"
if [[ ! -x "$app_binary" ]]; then
    echo "Build and sign the Debug Docky app before testing its Dock-side bridge." >&2
    exit 1
fi
# Temporarily suppresses/restarts the Apple Dock and restores its preferences.
gtimeout 30 "$app_binary" --dock-bridge-regression -ApplePersistenceIgnoreState YES
