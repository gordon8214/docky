#!/bin/bash
set -euo pipefail
# Dock is arm64e on Apple silicon; its injected payload must use that ABI.
bridge_source="${SRCROOT}/DockyDockBridge"
bridge_output="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/DockBridge"
mkdir -p "$bridge_output"
xcrun clang -fobjc-arc -dynamiclib -arch arm64e \
    -mmacosx-version-min=27.0 -framework AppKit -framework Security \
    "$bridge_source/payload.m" -o "$bridge_output/DockyDockBridge.dylib"
xcrun clang -arch arm64e -mmacosx-version-min=27.0 -framework Cocoa \
    "$bridge_source/loader.m" -o "$bridge_output/DockyDockLoader"
cp "$bridge_source/LICENSE-yabai.txt" "$bridge_output/LICENSE-yabai.txt"
bridge_identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [[ -z "$bridge_identity" ]]; then bridge_identity="-"; fi
codesign --force --sign "$bridge_identity" "$bridge_output/DockyDockBridge.dylib"
codesign --force --sign "$bridge_identity" --entitlements "$bridge_source/loader.entitlements" \
    "$bridge_output/DockyDockLoader"
