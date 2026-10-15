#!/bin/bash
set -euo pipefail
# Expected compilation under 5 seconds and tests under 1 second; hard limits 30s/5s.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
menu_test_output="$project_root/build/MenuNativeTests"
mkdir -p "$menu_test_output"
gtimeout 5 xcrun clang -arch arm64e -c "$project_root/DockyMenuBridge/dlopen-stub.s" -o "$menu_test_output/stub.o"
gtimeout 5 python3 "$project_root/DockyMenuBridge/Tests/check_stub.py" \
  "$menu_test_output/stub.o" "$project_root/DockyMenuBridge/loader.m"
gtimeout 30 xcrun clang -fobjc-arc -arch arm64 -mmacosx-version-min=27.0 \
  -framework AppKit -framework Security "$project_root/DockyMenuBridge/Tests/protocol.m" \
  -o "$menu_test_output/protocol"
codesign --force --sign - --identifier gt.quintero.Docky "$menu_test_output/protocol"
gtimeout 5 "$menu_test_output/protocol"
