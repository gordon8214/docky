#!/bin/zsh
set -euo pipefail
setopt null_glob

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/Docky.xcodeproj"
SCHEME="Docky"
CONFIGURATION="Release"
APP_NAME="Docky"
APPCAST_BASE_URL="${APPCAST_BASE_URL:-https://getdocky.com/releases}"
APPCAST_FILENAME="${APPCAST_FILENAME:-appcast.xml}"
MARKETING_VERSION="${MARKETING_VERSION:-1.0.1}"
BUILD_VERSION="${BUILD_VERSION:-$(date +%Y%m%d%H%M)}"
RELEASE_NOTES_FILE="${RELEASE_NOTES_FILE:-}"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-}"

BUILD_ROOT="$PROJECT_ROOT/build"
ARCHIVE_PATH="$BUILD_ROOT/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_ROOT/export"
UPDATES_PATH="$BUILD_ROOT/updates"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
ZIP_NAME="$APP_NAME-$MARKETING_VERSION-$BUILD_VERSION.zip"
ZIP_PATH="$UPDATES_PATH/$ZIP_NAME"
SPARKLE_BIN_DIR="${SPARKLE_BIN_DIR:-}"

if [[ -z "$SPARKLE_BIN_DIR" ]]; then
    candidates=("$HOME/Library/Developer/Xcode/DerivedData"/Docky-*/SourcePackages/artifacts/sparkle/Sparkle/bin)
    if (( ${#candidates[@]} > 0 )); then
        SPARKLE_BIN_DIR="$candidates[1]"
    fi
fi

GENERATE_APPCAST="$SPARKLE_BIN_DIR/generate_appcast"

if [[ ! -x "$GENERATE_APPCAST" ]]; then
    print -u2 "Sparkle generate_appcast tool not found at: $GENERATE_APPCAST"
    print -u2 "Build the app once in Xcode or override SPARKLE_BIN_DIR before running this script."
    exit 1
fi

mkdir -p "$BUILD_ROOT" "$UPDATES_PATH"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

cat > "$BUILD_ROOT/ExportOptions-DeveloperID.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>2KC3797KP9</string>
</dict>
</plist>
EOF

xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH"

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$BUILD_ROOT/ExportOptions-DeveloperID.plist"

if [[ ! -d "$APP_PATH" ]]; then
    print -u2 "Exported app not found at: $APP_PATH"
    exit 1
fi

"$PROJECT_ROOT/scripts/verify_architectures.sh" "$APP_PATH"

if [[ -n "$NOTARYTOOL_PROFILE" ]]; then
    xcrun notarytool submit "$APP_PATH" \
        --keychain-profile "$NOTARYTOOL_PROFILE" \
        --wait
    xcrun stapler staple "$APP_PATH"
else
    print "Skipping notarization because NOTARYTOOL_PROFILE is not set."
fi

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

if [[ -n "$RELEASE_NOTES_FILE" ]]; then
    cp "$RELEASE_NOTES_FILE" "$UPDATES_PATH/${ZIP_NAME:r}.md"
fi

"$GENERATE_APPCAST" "$UPDATES_PATH"

print
print "Update artifacts generated in: $UPDATES_PATH"
print "Upload the contents of this folder to: $APPCAST_BASE_URL/"
print "Expected appcast URL: $APPCAST_BASE_URL/$APPCAST_FILENAME"
