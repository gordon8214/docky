#!/bin/bash
set -euo pipefail

build_only=0
case "${1:-}" in
    "") ;;
    --build-only) build_only=1; shift ;;
    -h|--help)
        printf 'Usage: %s [--build-only]\n' "$0"
        exit 0
        ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 64 ;;
esac
[[ $# -eq 0 ]] || { printf 'Unexpected arguments\n' >&2; exit 64; }
[[ "$(uname -s)" == Darwin ]] || { printf 'Docky installation requires macOS\n' >&2; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/../../../.." && pwd -P)"
derived_data="$repo_root/build/InstallDerivedData"
app_path="$derived_data/Build/Products/Release/Docky.app"
installed_path="/Applications/Docky.app"
stage_dir=""
backup_path=""
replacement_started=0
replacement_verified=0

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

cleanup() {
    if [[ "$replacement_verified" -eq 0 ]] &&
        { [[ "$replacement_started" -eq 1 ]] || [[ -n "$backup_path" && -e "$backup_path" ]]; }; then
        rm -rf -- "$installed_path"
        if [[ -n "$backup_path" && -e "$backup_path" ]]; then
            if ! mv "$backup_path" "$installed_path"; then
                printf 'Restore failed; previous app preserved at %s\n' "$backup_path" >&2
                return
            fi
        fi
    fi
    [[ -z "$stage_dir" ]] || rm -rf -- "$stage_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

verify_app() {
    local path="$1"
    [[ -x "$path/Contents/MacOS/Docky" ]] || fail "Missing Docky executable: $path"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$path/Contents/Info.plist")" == gt.quintero.Docky ]] ||
        fail "Unexpected bundle identifier: $path"
    codesign --verify --deep --strict "$path" || fail "Signature verification failed: $path"
    "$repo_root/scripts/verify_architectures.sh" "$path"
}

running_pids() { pgrep -x "$1" || [[ $? -eq 1 ]]; }

wait_for_exit() {
    local name="$1" attempts="$2" attempt
    for ((attempt = 0; attempt < attempts; attempt++)); do
        [[ -z "$(running_pids "$name")" ]] && return 0
        sleep 0.5
    done
    [[ -z "$(running_pids "$name")" ]]
}

signal_copies() {
    local name="$1" signal="$2" pid
    while IFS= read -r pid; do
        [[ -z "$pid" ]] || kill "-$signal" "$pid" 2>/dev/null || true
    done < <(running_pids "$name")
}

[[ -f "$repo_root/Docky.xcodeproj/project.pbxproj" ]] || fail "Skill is outside a Docky checkout"
if [[ "$build_only" -eq 0 ]]; then
    [[ -w /Applications ]] || fail "/Applications is not writable"
    [[ ! -L "$installed_path" ]] || fail "Install destination is a symbolic link: $installed_path"
fi
mkdir -p "$derived_data"
printf 'Building Release from %s\n' "$repo_root"
xcodebuild -project "$repo_root/Docky.xcodeproj" -scheme Docky \
    -configuration Release -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived_data" build 2>&1 | tee "$derived_data/install-build.log"
verify_app "$app_path"
printf 'Build: Release succeeded; signature and embedded architectures verified\n'
[[ "$build_only" -eq 0 ]] || exit 0

# Stage before quitting so a copy or verification failure leaves Docky running.
stage_dir="$(mktemp -d /Applications/.docky-install.XXXXXX)"
ditto "$app_path" "$stage_dir/Docky.app"
verify_app "$stage_dir/Docky.app"

if [[ -n "$(running_pids Docky)" ]]; then
    # NSRunningApplication reaches every copy without launching an absent app.
    osascript -l JavaScript <<'JXA' &
ObjC.import('AppKit');
var apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier('gt.quintero.Docky');
for (var i = 0; i < apps.count; i++) {
    apps.objectAtIndex(i).terminate;
}
JXA
    quit_pid=$!
    wait_for_exit Docky 20 || true
    kill "$quit_pid" 2>/dev/null || true
    wait "$quit_pid" 2>/dev/null || true
    if ! wait_for_exit Docky 1; then
        signal_copies Docky TERM
        if ! wait_for_exit Docky 10; then
            signal_copies Docky KILL
            wait_for_exit Docky 4 || fail "Existing Docky copies did not exit"
        fi
    fi
fi
# The watchdog restores the system Dock after an ungraceful app exit.
if ! wait_for_exit DockyDockWatchdog 20; then
    fail "Docky watchdog is still running; replacement canceled"
fi
[[ -z "$(running_pids Docky)" ]] || fail "Docky restarted; replacement canceled"

backup_path="$stage_dir/previous.app"
if [[ -e "$installed_path" ]]; then
    mv "$installed_path" "$backup_path"
fi
replacement_started=1
mv "$stage_dir/Docky.app" "$installed_path"
verify_app "$installed_path"
replacement_verified=1
printf 'Installed: %s\n' "$installed_path"

open -n "$installed_path" || fail "Installed successfully, but launch failed"
launch_pid=""
for ((attempt = 0; attempt < 20; attempt++)); do
    launch_pid="$(ps -axo pid=,comm= | gawk '
        $0 ~ /^[[:space:]]*[0-9]+[[:space:]]+\/Applications\/Docky[.]app\/Contents\/MacOS\/Docky$/ && !pid { pid = $1 }
        END { if (pid) print pid }
    ')"
    [[ -z "$launch_pid" ]] || break
    sleep 0.5
done
[[ -n "$launch_pid" ]] || fail "Installed successfully, but no process from $installed_path appeared"
printf 'Launched: %s (PID %s)\n' "$installed_path" "$launch_pid"
