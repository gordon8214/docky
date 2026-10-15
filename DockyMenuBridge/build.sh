#!/bin/bash
set -euo pipefail
menu_source="${SRCROOT}/DockyMenuBridge"
menu_output="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/MenuBridge"
mkdir -p "$menu_output"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -dynamiclib -arch arm64 -arch arm64e \
  -mmacosx-version-min=27.0 -framework AppKit -framework Security \
  "$menu_source/payload.m" -o "$menu_output/DockyMenuBridge.dylib"
xcrun clang -arch arm64e -mmacosx-version-min=27.0 -framework Cocoa \
  "$menu_source/loader.m" -o "$menu_output/DockyMenuLoader"
menu_identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [[ -z "$menu_identity" ]]; then menu_identity=-; fi
codesign --force --sign "$menu_identity" "$menu_output/DockyMenuBridge.dylib"
codesign --force --sign "$menu_identity" --entitlements "${SRCROOT}/DockyDockBridge/loader.entitlements" "$menu_output/DockyMenuLoader"
cp "$menu_source/LICENSE-yabai.txt" "$menu_output/LICENSE-yabai.txt"
