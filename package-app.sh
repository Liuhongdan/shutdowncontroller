#!/bin/bash
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="ShutdownController"
BUILD_DIR="./build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

mkdir -p "$BUILD_DIR"
rm -rf "$APP_BUNDLE"

echo "Creating standard macOS .app directory structure..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "Writing Info.plist..."
cat << 'EOF' > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ShutdownController</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.ShutdownController</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ShutdownController</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

echo "Copying application icon..."
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
    echo "Icon successfully copied!"
else
    echo "Warning: AppIcon.icns not found in project folder."
fi

echo "Compiling Swift application..."
swiftc ShutdownApp.swift ContentView.swift ScheduleRules.swift -o "$BUILD_DIR/$APP_NAME-arm64" -target arm64-apple-macos13.0
swiftc ShutdownApp.swift ContentView.swift ScheduleRules.swift -o "$BUILD_DIR/$APP_NAME-x86_64" -target x86_64-apple-macos13.0
lipo -create \
    "$BUILD_DIR/$APP_NAME-arm64" \
    "$BUILD_DIR/$APP_NAME-x86_64" \
    -output "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
rm -f "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64"

echo "Success! Your app bundle is ready at:"
echo "👉 $APP_BUNDLE"
