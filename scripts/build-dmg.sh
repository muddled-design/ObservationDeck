#!/bin/bash
set -euo pipefail

# Build ClaudeMonitor.app and package it into a DMG for distribution.
# Usage:
#   ./scripts/build-dmg.sh                  # build with default version
#   ./scripts/build-dmg.sh --version 1.2.3  # build with specific version

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DERIVED_DATA="$PROJECT_DIR/.build/DerivedData"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="ClaudeMonitor"
VERSION="1.0.0"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--version X.Y.Z]"
            exit 1
            ;;
    esac
done

# Generate Xcode project if needed
if [ ! -d "$PROJECT_DIR/ObservationDeck.xcodeproj" ]; then
    echo "==> Generating Xcode project..."
    (cd "$PROJECT_DIR" && xcodegen generate)
fi

echo "==> Building $APP_NAME v$VERSION (release)..."
xcodebuild -project "$PROJECT_DIR/ObservationDeck.xcodeproj" \
    -scheme ClaudeMonitor \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$VERSION" \
    build 2>&1

# Locate built app
APP_BUNDLE="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: Built app not found at $APP_BUNDLE"
    exit 1
fi

echo "==> Creating DMG..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

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
