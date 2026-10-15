#!/bin/bash
set -euo pipefail
# Expected under 10 seconds after a Debug build, longer when some window has no
# AX element. Runtime budget: 30 seconds, plus any watch time.
# Requires an unlocked desktop and the app's existing capture/AX permissions.
# Pass --watch-registry <seconds> to print registry changes while you move,
# resize, minimize, or close windows. Set DOCKY_APP_BINARY to test another build.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_binary="${DOCKY_APP_BINARY:-$project_root/build/AppKitDerivedData/Build/Products/Debug/Docky.app/Contents/MacOS/Docky}"
watch_seconds=0
args=()
while (($#)); do
    case "$1" in
        --watch-registry)
            if [[ ! "${2:-}" =~ ^[0-9]+$ ]] || (( ${2:-0} == 0 )); then
                echo "--watch-registry needs a whole number of seconds" >&2
                exit 2
            fi
            watch_seconds=$2
            args+=("$1" "$2")
            shift 2
            ;;
        *)
            echo "Unknown argument: $1 (set DOCKY_APP_BINARY to choose the app)" >&2
            exit 2
            ;;
    esac
done
if [[ ! -x "$app_binary" ]]; then
    echo "Build the Debug Docky app before running the window registry regression." >&2
    exit 1
fi
# ${args[@]+...} keeps an empty array from tripping set -u in macOS's bash 3.2.
gtimeout $((30 + watch_seconds)) "$app_binary" --window-registry-regression ${args[@]+"${args[@]}"} \
    -ApplePersistenceIgnoreState YES
