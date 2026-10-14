#!/bin/bash
set -euo pipefail
# Expected under 10 seconds after a Debug build. Runtime budget: 30 seconds.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_binary="${1:-$project_root/build/AppKitDerivedData/Build/Products/Debug/Docky.app/Contents/MacOS/Docky}"
if [[ ! -x "$app_binary" ]]; then
    echo "Build the Debug Docky app before running system integration regressions." >&2
    exit 1
fi
# Requires a WindowServer session. The harness restores the previous native
# reservation on success and on thrown failures; it never changes Dock prefs.
gtimeout 30 "$app_binary" --dock-system-regression -ApplePersistenceIgnoreState YES
