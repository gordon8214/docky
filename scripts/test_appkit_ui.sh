#!/bin/bash
set -euo pipefail
# Expected under 15 seconds with a previously built Debug app. Runtime budget: 30s.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_binary="${1:-$project_root/build/AppKitDerivedData/Build/Products/Debug/Docky.app/Contents/MacOS/Docky}"
if [[ ! -x "$app_binary" ]]; then
    echo "Build the Debug Docky app before running its AppKit UI regressions." >&2
    exit 1
fi
gtimeout 30 "$app_binary" --appkit-ui-regression -ApplePersistenceIgnoreState YES
