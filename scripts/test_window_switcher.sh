#!/bin/bash
set -euo pipefail
# Expected under 15 seconds after a Debug build. Runtime budget: 45 seconds.
# Requires an unlocked desktop and the app's existing capture/AX permissions.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_binary="${1:-$project_root/build/AppKitDerivedData/Build/Products/Debug/Docky.app/Contents/MacOS/Docky}"
gtimeout -k 5 45 "$app_binary" --window-switcher-regression -ApplePersistenceIgnoreState YES
