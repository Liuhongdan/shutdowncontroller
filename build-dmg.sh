#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="ShutdownController"
VERSION="1.1.0"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_ROOT="$BUILD_DIR/$APP_NAME-dmg"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ -n "$NOTARY_PROFILE" && -z "$SIGNING_IDENTITY" ]]; then
    echo "NOTARY_PROFILE requires DEVELOPER_ID_APPLICATION to be set." >&2
    exit 1
fi

"$SCRIPT_DIR/package-app.sh"

if [[ -n "$SIGNING_IDENTITY" ]]; then
    echo "Signing app with Developer ID..."
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" \
        "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
else
    echo "Warning: building an unsigned DMG. Set DEVELOPER_ID_APPLICATION for distribution signing."
fi

echo "Preparing disk image contents..."
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
cp -R "$APP_BUNDLE" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
cp "$SCRIPT_DIR/INSTALL-UNINSTALL.txt" "$DMG_ROOT/"
rm -f "$DMG_PATH"

echo "Creating compressed DMG..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "Submitting DMG for notarization..."
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
fi

echo "DMG created at: $DMG_PATH"