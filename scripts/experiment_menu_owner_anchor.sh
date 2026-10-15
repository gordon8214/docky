#!/bin/bash
set -euo pipefail
# Explicit owner-side experiments. None of these payloads are bundled with Docky.
# Expected build under 10 seconds; AX requests and injection are individually bounded.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
experiment_output="$project_root/build/MenuOwnerExperiment"
experiment_identity="${DOCKY_MENU_SIGN_IDENTITY:--}"
experiment_action="${1:-build}"
mkdir -p "$experiment_output"

case "$experiment_action" in
  build|access|runtime|open-menu|move-control-center) ;;
  *) echo 'Usage: experiment_menu_owner_anchor.sh build|access|runtime|open-menu|move-control-center' >&2; exit 64 ;;
esac

xcrun clang -fobjc-arc -Wall -Wextra -Werror -arch arm64e -mmacosx-version-min=27.0 \
  -framework AppKit -framework ApplicationServices "$project_root/scripts/menu_host_probe.m" \
  -o "$experiment_output/menu_host_probe"
codesign --force --sign "$experiment_identity" --entitlements "$project_root/DockyDockBridge/loader.entitlements" \
  "$experiment_output/menu_host_probe"

if [[ "$experiment_action" == access || "$experiment_action" == runtime ]]; then
  experiment_probe_argument=--runtime
  if [[ "$experiment_action" == access ]]; then experiment_probe_argument=--task-access; fi
  gtimeout 15 "$experiment_output/menu_host_probe" "$experiment_probe_argument"
  exit
fi

python3 - "$project_root" "$experiment_output" <<'PY'
from pathlib import Path
import sys
root, output = map(Path, sys.argv[1:])
source = (root / 'DockyDockBridge/loader.m').read_text()
assert source.count('@"com.apple.dock"') == 1
for name, identifier in [('syncthing', 'com.github.xor-gate.syncthing-macosx'),
                         ('controlcenter', 'com.apple.controlcenter')]:
    (output / f'{name}-loader.m').write_text(source.replace('@"com.apple.dock"', f'@"{identifier}"'))
PY
for experiment_owner in syncthing controlcenter; do
  xcrun clang -arch arm64e -mmacosx-version-min=27.0 -framework Cocoa \
    "$experiment_output/$experiment_owner-loader.m" -o "$experiment_output/$experiment_owner-loader"
  codesign --force --sign "$experiment_identity" --entitlements "$project_root/DockyDockBridge/loader.entitlements" \
    "$experiment_output/$experiment_owner-loader"
done

experiment_request="$experiment_output/request.json"
experiment_report="$experiment_output/report.log"
# A new image path permits another one-shot constructor without restarting its owner.
experiment_image="$experiment_output/anchor-$(uuidgen).dylib"
if [[ "$experiment_action" == move-control-center ]]; then
  experiment_source=menu_window_anchor.m
  experiment_owner=controlcenter
  experiment_bundle=com.apple.controlcenter
  experiment_label='Control Center'
else
  experiment_source=menu_owner_anchor.m
  experiment_owner=syncthing
  experiment_bundle=com.github.xor-gate.syncthing-macosx
  experiment_label=Syncthing
fi
xcrun clang -fobjc-arc -Wall -Wextra -Werror -dynamiclib -arch arm64 -arch arm64e \
  -mmacosx-version-min=27.0 -framework AppKit "-DDOCKY_ANCHOR_REQUEST=\"$experiment_request\"" \
  "$project_root/DockyDockBridge/$experiment_source" -o "$experiment_image"
codesign --force --sign "$experiment_identity" "$experiment_image"
if [[ "$experiment_action" == build ]]; then
  xcrun clang -fobjc-arc -Wall -Wextra -Werror -dynamiclib -arch arm64 -arch arm64e \
    -mmacosx-version-min=27.0 -framework AppKit "-DDOCKY_ANCHOR_REQUEST=\"$experiment_request\"" \
    "$project_root/DockyDockBridge/menu_window_anchor.m" -o "$experiment_output/window-anchor.dylib"
  codesign --force --sign "$experiment_identity" "$experiment_output/window-anchor.dylib"
  echo "Built owner experiments in $experiment_output"
  exit
fi

gtimeout 15 "$experiment_output/menu_host_probe" --anchor-request "$experiment_request" "$experiment_report" \
  "$experiment_bundle" "$experiment_label"
experiment_pid="$(python3 - "$experiment_request" <<'PY'
import json, sys
with open(sys.argv[1]) as source:
    print(int(json.load(source)['pid']))
PY
)"
gtimeout 5 "$experiment_output/$experiment_owner-loader" "$experiment_image" "$experiment_pid"
echo "Owner experiment dispatched. Read $experiment_report for its result."
