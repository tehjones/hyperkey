#!/bin/bash
set -euo pipefail

APP_NAME="HyperKey"
BUNDLE_ID="com.sergey.hyperkey"
VERSION="0.1.5"
ICON_FILE="Resources/HyperKey.icns"
APP_DIR="$APP_NAME.app"

# Build release
swift build -c release

# Create .app bundle structure
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Copy icons
cp "$ICON_FILE" "$APP_DIR/Contents/Resources/HyperKey.icns"
cp Resources/MenuBarIcons/*.png "$APP_DIR/Contents/Resources/"

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>
    <string>HyperKey</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "Built $APP_DIR"
echo ""
echo "To install:"
echo "  cp -r $APP_DIR /Applications/"
echo ""
echo "Then open HyperKey from /Applications and grant Accessibility access when prompted."
