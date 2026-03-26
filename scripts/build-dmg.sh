#!/bin/bash
set -euo pipefail

# Build ClaudeMonitor.app bundle and package it into a DMG for distribution.
# Usage:
#   ./scripts/build-dmg.sh                  # unsigned build
#   ./scripts/build-dmg.sh --sign "Developer ID Application: Your Name (TEAMID)"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="ClaudeMonitor"
BUNDLE_ID="com.begger.claudemonitor"
VERSION="1.0.0"

# Parse arguments
CODESIGN_IDENTITY=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --sign)
            CODESIGN_IDENTITY="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--sign \"Developer ID Application: ...\"] [--version X.Y.Z]"
            exit 1
            ;;
    esac
done

echo "==> Building $APP_NAME v$VERSION (release)..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

BINARY="$BUILD_DIR/release/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    # Apple Silicon vs Intel path
    BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"
fi

echo "==> Creating .app bundle..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$BINARY" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# Create Info.plist
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>Observation Deck</string>
    <key>CFBundleDisplayName</key>
    <string>Observation Deck</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

# Code sign if identity provided
if [ -n "$CODESIGN_IDENTITY" ]; then
    echo "==> Code signing with: $CODESIGN_IDENTITY"
    codesign --force --deep --options runtime \
        --sign "$CODESIGN_IDENTITY" \
        "$APP_BUNDLE"
    echo "==> Verifying signature..."
    codesign --verify --verbose=2 "$APP_BUNDLE"
else
    echo "==> Skipping code signing (use --sign to sign)"
    # Ad-hoc sign so macOS doesn't immediately quarantine
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo "==> Creating DMG..."
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
DMG_TEMP="$DIST_DIR/dmg-staging"

rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app to staging
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# Create a symlink to /Applications for drag-install
ln -s /Applications "$DMG_TEMP/Applications"

# Create the DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_PATH" 2>&1

rm -rf "$DMG_TEMP"

echo ""
echo "==> Done!"
echo "    App:  $APP_BUNDLE"
echo "    DMG:  $DMG_PATH"
echo "    Size: $(du -h "$DMG_PATH" | cut -f1)"

# Print SHA256 for Homebrew formula
SHA256=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)
echo "    SHA256: $SHA256"
